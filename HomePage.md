# THIS GUIDE IS A WORK IN PROGRESS. PROCEED WITH CAUTION :)

Topics covered
==============
* [Overview](#overview)
* [Verify PL/R installation](#installation)
* [Verify parallelization](#parallelization)
* [Installing packages](#packages)
* [Notes on permissions](#permissions)
* [Best practices](#bestpractices)
  * [Data prep](#dataprep)
  * [Return types](#returntypes)
  * [UDA & UDF](#uda)
  * [RPostgreSQL](#rpostgresql)
* [Memory limitations](#memory)
* [Persisting R models in database](#persistence)
* [Data types](#datatypes)
* [Performance testing](#performance)
* [Plotting](#plotting)

## <a name="overview"/> Overview 
There are lots of different ways to use R with the Greenplum database. This documentation should be considered a guide for practitioners and *not* official documentation. The intention is to give pragmatic tips on how to navigate GP+R. 

PL/R provides a connection from the database to R, which is running on every segment of the DCA, to allow you to write procedural functions in R. In this setup R is not a client application that runs on the desktop like pgadmin. It runs on each segment of the server.

## Getting started with this guide

Download data into linux file system, and note path (linux prompt)
```
wget http://archive.ics.uci.edu/ml/machine-learning-databases/abalone/abalone.data
pwd
```

Create table in GP; note that "/path/to/data" is the path 
returned by 'pwd' in the previous line of code (psql prompt)

```
DROP TABLE IF EXISTS abalone;
CREATE TABLE abalone (sex text, length float8, diameter float8, height float8, whole_weight float8, shucked_weight float8, viscera_weight float8, shell_weight float8, rings float8) 
DISTRIBUTED RANDOMLY;
COPY abalone FROM '/path/to/data/abalone.data' WITH CSV;
```

## <a name="installation"/> Verify installation
CONTENT TBD

### Verify R installation
CONTENT TBD

### Verify PL/R installation
CONTENT TBD

## <a name="parallelization"/> Verify parallelization
Congratulations, you've just parellelized your first PL/R algorithm in GPDB. Or have you? In this section we will describe 3 sanity check to ensure that your code is actually running in parallel.

We can quickly verify if a PL/R function is indeed running on all segment as follows:

```SQL
drop function if exists plr_parallel_test;
create function plr_parallel_test() 
returns text 
as 
$$ 
	return (system('hostname',intern=TRUE)) 
$$ language 'plr';

```

The function essentially returns the hostname of the segment node on which it is executing.
By invoking the function for rows from a table that is distributed across all segments, we can verify if we indeed
see all the segments in the output.

```SQL
gpadmin=# select distinct plr_parallel_test() from abalone;
 plr_parallel_test 
------------------
 sdw1
 sdw10
 sdw11
 sdw12
 sdw13
 sdw14
 sdw15
 sdw16
 sdw2
 sdw3
 sdw4
 sdw5
 sdw6
 sdw7
 sdw8
 sdw9
(16 rows)

```

We can see that all 16 segment hosts were returned in the result, which means all nodes executed our PL/R function.


### Timing
An alternative way to verify whether your code is running in parallel is to do timed performance testing. This method is laborious, but can be helpful in precisely communicating the speedup achieved through parallelization. 

Using the abalone dataset, we show how to compare the timing results from an implementation that builds models sequentially with the version that builds them in parallel. First we create a PL/R function which builds a linear regression to predict the age of an abalone (determined by counting the number of rings) from physical measurements. The function returns the coefficients for each of the linear predictors. 

```SQL
    DROP FUNCTION IF EXISTS plr_lm( sex text[], length float8[], diameter float8[],
            height float8[], whole_weight float8[], 
            shucked_weight float8[], viscera_weight float8[], 
            shell_weight float8[], rings float8[] );
    CREATE OR REPLACE FUNCTION plr_lm( sex text[], length float8[], 
            diameter float8[], height float8[], whole_weight float8[], 
            shucked_weight float8[], viscera_weight float8[], 
            shell_weight float8[], rings float8[] ) 
    RETURNS FLOAT8[] AS 
    $$
      abalone   = data.frame( sex, length, diameter, height, whole_weight, 
            shucked_weight, viscera_weight, shell_weight, rings ) 

      m = lm(formula = rings ~ ., data = abalone)

      coef( m )
    $$
    LANGUAGE 'plr';
```

Next we convert the dataset (as described in section XX) to an array representation and store the results in a new table called `abalone_array`.

```SQL
    -- Create a vectorized version of the data
    -- This table has a single row, and 9 columns
    -- Each element contains all of the elements for the
    -- respective column as an array 
    DROP TABLE IF EXISTS abalone_array;
    CREATE TABLE abalone_array AS 
    SELECT 
      array_agg(sex)::text[] as sex, 
      array_agg(length)::float8[] as length,
      array_agg(diameter)::float8[] as diameter, 
      array_agg(height)::float8[] as height,
      array_agg(whole_weight)::float8[] as whole_weight, 
      array_agg(shucked_weight)::float8[] as shucked_weight,
      array_agg(viscera_weight)::float8[] as viscera_weight, 
      array_agg(shell_weight)::float8[] as shell_weight, 
      array_agg(rings)::float8[] as rings
    FROM abalone
    DISTRIBUTED RANDOMLY;
```

Now that we have a PL/R function definition and the dataset prepared in an array representation, we can call the function like this:

```
    SELECT plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, viscera_weight, shell_weight, rings )
    FROM abalone_array;
    ---------------
    (1 row)

    Time: 47.341 ms
```

Note that creating a single model takes about 47 ms. 

But what if we want to create multiple models? For instance, imagine the abalone were sampled from 64 different regions and we hypothesize that the physical characteristics vary based on region. In this situation, we may want to construct multiple models to capture the region-specific effects. To simulate this scenario we will simply replicate the same dataset 64 times and build 64 identical models. We construct the models sequentially and in parallel and compare the execution time. 

To build the models sequentially we create a simple PGSQL function that builds linear models in a loop using the `plr_lm` function we created earlier: 

```SQL
    DROP FUNCTION IF EXISTS IterativePLRModels( INTEGER );
    CREATE OR REPLACE FUNCTION IterativePLRModels( INTEGER ) 
    RETURNS SETOF TEXT 
    AS $BODY$
    DECLARE
      n ALIAS FOR $1;
    BEGIN
      FOR i IN 1..n LOOP
        RAISE NOTICE 'Processing %', i;
        PERFORM plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, viscera_weight, shell_weight, rings )
        FROM abalone_array;
        RETURN NEXT i::TEXT;
      END LOOP;
    END
    $BODY$
      LANGUAGE plpgsql;
```

The function accepts a single argument, which specifies the number of iterations. For this example we set that value to 64 and expect that the running time will be roughly the length of time it took to build a single model multipled by the number of iterations: 47 * 64 = 3008 ms.

```SQL
    SELECT IterativePLRModels( 64 );
    -----------
    (64 rows)

    Time: 2875.609 ms
```

Pretty darn close!

Next let's construct the models in parallel. In order to do this we must replicate the abalone data and distribute it across the GPDB segments. The PGSQL function below creates a new table called `abalone_array_replicates` that contains copies of the abalone dataset indexed by a distkey and distributed randomly across the segments. 

```SQL
    DROP FUNCTION IF EXISTS ReplicateAbaloneArrays( INTEGER );
    CREATE OR REPLACE FUNCTION ReplicateAbaloneArrays( INTEGER ) 
    RETURNS INTEGER AS
    $BODY$
    DECLARE
      n ALIAS FOR $1;
    BEGIN
      DROP TABLE IF EXISTS abalone_array_replicates;
      CREATE TABLE abalone_array_replicates AS
      SELECT 1 as distkey, * FROM abalone_array
      DISTRIBUTED randomly;

      FOR i IN 2..n LOOP
        INSERT INTO abalone_array_replicates SELECT i as distkey, * FROM abalone_array;
      END LOOP;

      RETURN n;
    END;
    $BODY$
      LANGUAGE plpgsql;
```

The function accepts a single argument, which specifies the number of copies to make: 
```
    -- Create 64 copies
    SELECT ReplicateAbaloneArrays( 64 );
```

Now we have a new table `abalone_array_replicates` that contains 64 rows and 9 columns in array representation, simulating measurements of 64 different types of abalone collected from different regions. We are now ready to construct 64 models in parallel. If the parallelization were perfectly efficient, the expected running time would be the running time of a single model, multiplied by the number of models, divided by the number of segments: (47 * 64) / 96 ~= 31 ms!

```SQL
    SELECT plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, viscera_weight, shell_weight, rings )
    FROM abalone_array_replicates;
    -----------------
    (64 rows)

    Time: 183.937 ms
```

Of course, parallelization aint perfect. There is overhead and other stuff. 

![alt text](https://github.com/zimmeee/gp-r/blob/master/figures/RowDistAcrossSegments.png?raw=true "Row distribution across segments")

### Command center
CONTENT TBD

## <a name="packages"/> R packages
The trick to installing R packages on the DCA is that each segment has it's own R instance running and thus each segment needs its own version of all of the required packages. At a high-level, the steps for installing R packages on a DCA are:

1. Get the package tars from CRAN (`wget`)
2. Copy the tar to all the segments on the DCA (`gpscp`)
3. Install the package (`gpssh`, then `R CMD INSTALL`)

R packages are the special sauce of R. This section explains how to check whether a package is installed and how to install new packages.

### Check R package installation

The simplest way to check if the requires R packages are available for PL/R is to gpssh into 
all the nodes and test if you are able to find the version of the required package. All the nodes
should return the correct version of the package, if the installation was successful.

```
gpssh -f all_hosts
=> echo "packageVersion('rpart')" | R --no-save

[sdw11] > packageVersion('rpart')
[sdw11] [1] ‘3.1.49’
[ sdw9] > packageVersion('rpart')
[ sdw9] [1] ‘3.1.49’
.
.
.
```

If the package is unavailable, the above code will error out. In the snippet below, we check for the version of the HMM package
in our installation. As there is no such package installed, the command will not execute successfully.

```
gpssh -f all_hosts
=> echo "packageVersion('hmm')" | R --no-save
[ sdw2] > packageVersion('hmm')
[ sdw2] Error in packageVersion("hmm") : package ‘hmm’ not found
[ sdw2] Execution halted
[ sdw3] > packageVersion('hmm')
[ sdw3] Error in packageVersion("hmm") : package ‘hmm’ not found
[ sdw3] Execution halted

```

Now, for whatever reason, if you do not have access to SSH into the GPDB or you prefer to only deal with 
UDFs to tell you if a PL/R package is present or absent, then you can write UDFs like the following:

A simple test if a package can be loaded can be done by this function:

```SQL
CREATE OR REPLACE FUNCTION R_test_require(fname text)
RETURNS boolean AS
$BODY$
    return(require(fname,character.only=T))
$BODY$
LANGUAGE 'plr';
```

If you want to check for a package called 'rpart', you would do
```SQL
SELECT R_test_require('rpart');
```

And it will return `TRUE` if the package could be loaded and `FALSE` if it couldn't. However, this only works on the node that you are currently logged on to.

To test the R installations on all nodes you would first create a dummy table with a series of integers that will be stored on different nodes in GPDB, like this:

```SQL
DROP TABLE IF EXISTS simple_series;
CREATE TABLE simple_series AS (SELECT generate_series(0,1000) AS id);
```

Also, since we want to know which host we are on we create a function to tell us:

```SQL
CREATE OR REPLACE FUNCTION R_return_host()
RETURNS text AS
$BODY$
  return(system("hostname",intern=T))
$BODY$
LANGUAGE 'plr';
```

Now we can check for each id (ids are stored on different nodes) if rpart is installed like this:
```SQL
DROP TABLE IF EXISTS result_nodes;
CREATE TABLE result_nodes AS 
    (SELECT id, R_return_host() AS hostname, R_test_require('rpart') AS result 
    FROM simple_series group by id); 
```

`result_nodes` is a table that contains for every id, the host that it is stored on as `hostname`, and the result of `R_test_require` as result. Since we only want to know for every host once, we group by `hostname` like this:

```SQL
select hostname, bool_and(result) AS host_result 
FROM result_nodes 
GROUP BY hostname 
ORDER BY hostname;
```

For a hostname where `R_test_require` returned true for all ids, the value in the column `host_result` will be true. If on a certain host the package couldn't be loaded, `host_result` will be false.

### Installing R packages

Before installing the packages for PL/R ensure that you are referring to the right R binary in your PATH and also ensure that the environment variable R_HOME
is referring to the right location where you installed R. These paths should be identical on all master and segment nodes.

Some users typically have a separate stand-alone installation of R on just the master node. If this is the case
with your installation, ensure that this is does not conflict with installation you need for PL/R to run on multiple segments.


For a given R library, identify all dependent R libraries and each library’s web url.  This can be found by selecting the given package from the following navigation page: 
http://cran.r-project.org/web/packages/available_packages_by_name.html 

From the page for the `arm` library, it can be seen that this library requires the following R libraries: `Matrix`, `lattice`, `lme4`, `R2WinBUGS`, `coda`, `abind`, `foreign`, `MASS`

From the command line, use wget to download the required libraries' `tar.gz` files to the master node:

```
wget http://cran.r-project.org/src/contrib/arm_1.5-03.tar.gz
wget http://cran.r-project.org/src/contrib/Archive/Matrix/Matrix_1.0-1.tar.gz
wget http://cran.r-project.org/src/contrib/Archive/lattice/lattice_0.19-33.tar.gz
wget http://cran.r-project.org/src/contrib/lme4_0.999375-42.tar.gz
wget http://cran.r-project.org/src/contrib/R2WinBUGS_2.1-18.tar.gz
wget http://cran.r-project.org/src/contrib/coda_0.14-7.tar.gz
wget http://cran.r-project.org/src/contrib/abind_1.4-0.tar.gz
wget http://cran.r-project.org/src/contrib/foreign_0.8-49.tar.gz
wget http://cran.r-project.org/src/contrib/MASS_7.3-17.tar.gz
```

Using `gpscp` and the hostname file, copy the `tar.gz` files to the same directory on all nodes of the Greenplum cluster.  Note that this may require root access. (note: location of host file may be different. On our DCA its /home/gpadmin/all_hosts)

```
gpscp -f /home/gpadmin/hosts_all lattice_0.19-33.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/hosts_all Matrix_1.0-1.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/hosts_all abind_1.4-0.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/hosts_all coda_0.14-7.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/hosts_all R2WinBUGS_2.1-18.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/hosts_all lme4_0.999375-42.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/hosts_all MASS_7.3-17.tar.gz =:/home/gpadmin
gpscp -f /home/gpadmin/hosts_all arm_1.5-03.tar.gz =:/home/gpadmin
```

`gpssh` into all segments (`gpssh -f /home/gpadmin/all_hosts`).  Install the packages from the command prompt using the `R CMD INSTALL` command.  Note that this may require root access 

```
R CMD INSTALL lattice_0.19-33.tar.gz Matrix_1.0-1.tar.gz abind_1.4-0.tar.gz coda_0.14-7.tar.gz R2WinBUGS_2.1-18.tar.gz lme4_0.999375-42.tar.gz MASS_7.3-17.tar.gz arm_1.5-03.tar.gz
```

Check that the newly installed package is listed under the `$R_HOME/library` directory on all the segments (convenient to use `gpssh` here as well).

### Package versions
Sometimes the current version of a package has dependencies on an earlier version of R. If this happens, you might get an error message like:

```
In getDependencies(pkgs, dependencies, available, lib) :
  package ‘matrix’ is not available (for R version 2.13.0)
```

Fortunately, there are older versions of most packages available in the CRAN archive. One heuristic we’ve found useful is to look at the release date of the R version installed on the machine. At the time of writing, it is v2.13 on our analytics DCA, which was released on 13-Apr-2011 (http://cran.r-project.org/src/base/R-2/). Armed with this date, go to the archive folder for the package you are installing and find the version that was released immediately prior to that date. For instance, the v1.5.3 of the package `glmnet` was released on 01-Mar-2011 and should be compatible with R v2.13 (http://cran.r-project.org/src/contrib/Archive/glmnet/ )

## <a name="packages"/> Notes on permissions
R is an [untrusted language](http://www.postgresql.org/docs/current/interactive/catalog-pg-language.html). Only superusers can create functions in untrusted languages. A discussion as to whether granting super user privileges on the database is acceptable needs to be an explicit step in selecting PL/R for your analytics project. 

This is what happens when you try to create a PL/R function when you aren't a superuser:

``` 
ERROR:  permission denied for language plr

********** Error **********

ERROR: permission denied for language plr
SQL state: 42501
```

You do not need superuser priveleges to EXECUTE a PL/R function, only to CREATE a PL/R function. You can do:

Non-superusers *can run* a PL/R function that was created by a superuser. In the GP Admin Guide there is a section entitled 'Managing Object Privileges' which outlines how to grant priveleges to other roles. 

GRANT USAGE privilege to the account 
http://lists.pgfoundry.org/pipermail/plr-general/2010-August/000441.html

## <a name="bestpractices"/> Best practices
CONTENT TBD

### Data preparation
CONTENT TBD

### Return types
CONTENT TBD

### UDA & UDF
CONTENT TBD

### RPostgreSQL
The [RPostgreSQL package](http://cran.r-project.org/web/packages/RPostgreSQL/index.html) provides a database interface and PostgreSQL driver for R that is compatible with the Greenplum database. This connection can be used to query the database in the normal fashion from within R code. We have found this package to be helpful for prototyping, working with datasets that can fit in-memory, and building visualizations. Generally speaking, using the RPostgreSQL interface does not lend itself to parallelization.  

Using RPostgreSQL has 3 steps: (i) create a database driver for PostgreSQL, (ii) connect to a specific database (iii) execute the query on GPDB and return results. 

#### 1) Local development
RPostgreSQL can be used in a local development environment to connect to a remote GPDB instance. Queries are processed in parallel on GPDB and results are returned in the familiar R data frame format. Use caution when returning large resultsets as you may run into the memory limitations of your local R instance. To ease troubleshooting, it can be helpful to develop/debug the SQL using your GPDB tool of choice (e.g. pgAdmin) before using it in R. 

```splus
    DBNAME = 'marketing'
    HOST   = '10.110.134.123'

    # Create a driver
    drv <- dbDriver( "PostgreSQL" )
    # Create the database connection
    con <- dbConnect( drv, dbname = DBNAME, host = HOST )

    # Create the SQL query string. Include a semi-colon to terminate
    querystring =   'SELECT countryname, income, babies FROM country_table;'
    # Execute the query and return results as a data frame
    countries   = dbGetQuery( con, querystring )

    # Plot the results
    plot( countries$income, countries$babies )
```

#### 2) PL/R Usage
RPostgreSQL can also be used from within a PL/R function and deployed on the host GPDB instance. This bypasses the PL/R pipe for data exchange in favor of the DBI driver used by RPostgreSQL. In certain tests we have found the RPostgreSQL data exchange to be faster than the PL/R interface [NOTE: We should explore/verify this claim]. The primary benefit of using this interface over the standard PL/R interface is that datatype conversions happen automatically; one need not specify all of the columns and their datatypes to pass to the function ahead of time. Sensible conversions are done automatically, including conversion of strings to factors which can be helpful in downstream processes. 

While RPostgreSQL can be quite useful in a development context, don't be fooled. It is not a good path towards actual parallelization of your R code. Because the code in the PL/R function accesses database objects it cannot safely be called in a distributed manner. This will lead to errors such as:

```SQL
    DROP FUNCTION IF EXISTS my_plr_error_func( character );
    CREATE OR REPLACE FUNCTION my_plr_error_func( character ) 
    RETURNS INTEGER AS 
    $$
      library("RPostgreSQL")

      drv <- dbDriver( "PostgreSQL" )
      con <- dbConnect( drv, dbname = arg1 )

      querystring = 'SELECT reviewid FROM sample_model_data;'
      model.data  = dbGetQuery( con, querystring )

      16
    $$
    LANGUAGE 'plr';
```

This returns without error, but does not run in parallel
```SQL
    SELECT my_plr_error_func( 'zimmen' );
```

This produces the error below
```
    SELECT my_plr_error_func( 'zimmen' ) 
    FROM sample_model_data;

    ********** Error **********

    ERROR: R interpreter expression evaluation error  (seg55 slice1 sdw3:40001 pid=1676)
    SQL state: 22000
    Detail: 
         Error in pg.spi.exec(sql) : 
      error in SQL statement : function cannot execute on segment because it accesses relation "public.sample_model_data"
         In R support function pg.spi.exec
    In PL/R function my_plr_error_func
```

GPDB is complaining because you are trying to access a table directly from a segment, which breaks the whole notion of coordination between the master node and its segments. Therefore, you cannot specify a from clause in your PL/R function when you make an RPostgreSQL call from within that function. 

#### Alternative
For the adventerous, the RPostgreSQL package provides more granular control over execution. An equivalent to dbGetQuery is to first submit the SQL to the database engine using dbSendQuery and then fetch the results: 

```splus
drv <- dbDriver( "PostgreSQL" )
con <- dbConnect( drv )
res <- dbSendQuery( con, "SELECT * FROM sample_model_data;" )
data <- fetch( res, n = -1 ) 
```

Note that the fetch function has a parameter, `n`, which sets the maximum number of records to retrieve. You probably always want to set this value to -1 to retrieve all of the records. I'm not sure why you would ever use this instead of the simpler dbGetQuery. 

## <a name="memory"/> Memory limitations
CONTENT TBD

## <a name="persistence"/> Persisting R models in database
One benefit of using PL/R on an MPP database like Greenplum is the ability to perform scoring in parallel across all the segments.
If you've trained a GLM model for instance, you could save a serialized version of this model in a database table and de-serialize it when needed and use it for scoring.

Typically the models are built once or are trained periodically depending on what the application may be, but the scoring may have to happen in real-time as new data becomes available.
If the data to be scored is stored in a table distributed across the segments on GPDB, then by ensuring the trained models are also distributed across the same segments, we
can achieve parallel scoring through PL/R.

The simplest approach would be to serialize the entire model into a byte array and store it in a table,
although not all parameters of the R model are required for scoring. For example, for linear or logistic regression we only
need the coefficients of the features to perform scoring. Advanced users should be able to extract only the relevant
parameters from the model and serialize them into a byte array on a table. This will improve scoring speed
as the segment nodes won't have to de-serialize large byte arrays. Another optimization that will speed up scoring will be
to pre-load the models into memory on the segment nodes - so that models are not de-serialized for every PL/R
function call. In both these cases the user will have to write additional logic beside the scoring itself, for the optimization.

In the sample code shown below we demonstrate some of these optimizations. This guide is work in progress
and in the upcoming versions we will include more examples to optimize the scoring function.

Here is a PL/R function that demonstrates how a trained GLM model can be serialized as a byte array.
The sample table patient_history_train is included in the data folder of this repo.

```SQL
	DROP FUNCTION IF EXISTS gpdemo.mdl_save_demo();
	CREATE FUNCTION gpdemo.mdl_save_demo() 
        RETURNS bytea 
        AS
	$$
	     #Read the previously created patient_history training set
	     dataset <- pg.spi.exec('select * from gpdemo.patient_history_train');

	     # Use the subset function to select a subset of the columns
             # Indices 2:6 are age, gender, race, marital status and bmi
             # Indices 14:20 are med_cond1 to med_cond7
             # Index 26 is the label 'infection cost'
	     ds = subset(dataset,select=c(2:6,14:20, 26))

	     #Define text  columns to be factor types
	     #These include gender, race, marital_status	     
	     ds$gender = as.factor(ds$gender)
	     ds$race = as.factor(ds$race)
	     ds$marital_status = as.factor(ds$marital_status)

	     #Fit a GLM
	     mdl = glm(formula = infection_cost ~ age +
				  gender +
				  race +
				  marital_status +
				  bmi +
				  med_cond1 +
				  med_cond2 +
				  med_cond3 +
				  med_cond4 +
				  med_cond5 +
				  med_cond6 +
				  med_cond7 
			, family = gaussian, data=ds)

             #Remove the data from the model (we only want to store the model, not the training set
             #mdl$data = NULL
             #mdl$qr = qr(qr.R(mdl$qr))
	     #The model is serialized and returned as a bytearray
	     return (serialize(mdl,NULL))
	$$
	LANGUAGE 'plr';
```

Here is a PL/R function to read the serialized PL/R model and apply it for scoring.

```SQL
	DROP FUNCTION IF EXISTS gpdemo.mdl_load_demo(bytea);
	CREATE FUNCTION gpdemo.mdl_load_demo(mdl bytea) 
        RETURNS setof gpdemo.glm_result_type 
        AS
	$$
	     #R-code goes here.
	     mdl <- unserialize(mdl)
	     cf <- coef(summary(mdl))
	     rows = dimnames(cf)[1]
	     #Create a data frame and pass that as a result
	     result = data.frame(params=rows[[1]],estimate=cf[,1],error=cf[,2],z_val=cf[,3],pr_z=cf[,4])
	     return (result)
	$$
	LANGUAGE 'plr';
```

Here is the PL/R function which demonstrate the parallel scoring using the GLM model we trained in the example above.


```SQL
	DROP FUNCTION IF EXISTS gpdemo.mdl_score_demo( bytea, 
							integer,
							text,
							text,
							text,
							double precision,
							integer,
							integer,
							integer,
							integer,
							integer,
							integer,
							integer
						      );
	CREATE FUNCTION gpdemo.mdl_score_demo( mdl bytea, 
						age integer,
						gender text,
						race text,
						marital_status text,
						bmi double precision,
						med_cond1 integer,
						med_cond2 integer,
						med_cond3 integer,
						med_cond4 integer,
						med_cond5 integer,
						med_cond6 integer,
						med_cond7 integer	
					      ) 
	RETURNS numeric AS
	$$
	     if (pg.state.firstpass == TRUE) {
	     	#Unserialize the model (i.e reconstruct it from its binary form).
	        assign("gp_plr_mdl_score", unserialize(mdl) ,env=.GlobalEnv)
	        assign("pg.state.firstpass", FALSE, env=.GlobalEnv)
	     }


	     #Read the test set from the previously created table  
	     test_set <- data.frame(
					age = age,
					gender = gender,
					race = race,
					marital_status = marital_status, 
					bmi =  bmi,
					med_cond1 =  med_cond1,
					med_cond2 =  med_cond2,
					med_cond3 =  med_cond3,
					med_cond4 =  med_cond4,
					med_cond5 =  med_cond5,
					med_cond6 =  med_cond6,
					med_cond7 =  med_cond7  	
			            );
	     #Perform prediction
	     pred <- predict(gp_plr_mdl_score, newdata=test_set, type="response"); 

	     return (pred)
	$$
	LANGUAGE 'plr';

```

The training, loading and scoring functions can be invoked from SQL like so :

```SQL
	-- Compute R square (coefficient of determination)
	-- R_square = (1 - SS_err/SS_tot)
	select 'PL/R glm model '::text as model, 
	       (1.0 - sum(ss_err)*1.0/sum(ss_tot)) as R_square
	from
	(
		select instance_num, 
		(infection_cost_actual - (select avg(infection_cost) from gpdemo.patient_history_test) )^2.0 as ss_tot,
		(infection_cost_actual -  infection_cost_predicted)^2.0 as ss_err,		
		1 as cnt
		from
		(
			-- Show actual vs predicted values for the infection cost
			select row_number() over (order by random()) as instance_num, 
				infection_cost as infection_cost_actual,
				gpdemo.mdl_score_demo ( mdls.model, 
							age,
							gender,
							race,
							marital_status,
							bmi,
							med_cond1,
							med_cond2,
							med_cond3,
							med_cond4,
							med_cond5,
							med_cond6,
							med_cond7		
						      ) as infection_cost_predicted 
			from gpdemo.plr_mdls mdls, gpdemo.patient_history_test test limit 10
		) q1
	) q2 group by cnt;
```

## <a name="datatypes"/> Data types
CONTENT TBD

## <a name="performance"/> Performance testing
CONTENT TBD

## <a name="plotting"/> Plotting
CONTENT TBD


```
$ cd your_repo_root/repo_name
$ git fetch origin
$ git checkout gh-pages
```

```SQL
DROP TABLE IF EXISTS abalone_array;
CREATE TABLE abalone_array AS 
SELECT 
	array_agg(sex)::text[] as sex, 
	array_agg(length)::float8[] as length,
	array_agg(diameter)::float8[] as diameter, 
	array_agg(height)::float8[] as height,
	array_agg(whole_weight)::float8[] as whole_weight, 
	array_agg(shucked_weight)::float8[] as shucked_weight,
	array_agg(viscera_weight)::float8[] as viscera_weight, 
	array_agg(shell_weight)::float8[] as shell_weight, 
	array_agg(rings)::float8[] as rings
FROM abalone
DISTRIBUTED RANDOMLY;
```

### Sample R code syntax highlighting

```splus
m = lm(formula = rings ~ ., data = abalone)

x = readLines(pipe("pbpaste"))
y = table(x)
barplot( y[order( as.integer(rownames(y)) )], xlab='Segment ID', 
		 ylab='Number of rows', main = 'Row distribution across segments' )
```

### Authors and Contributors
This document is a project by Woo Jung (@wjjung317), Srivatsan 'Vatsan' Ramanujam (@vatsan) and Noah Zimmerman (@zimmeee)
