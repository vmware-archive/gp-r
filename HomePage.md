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

## <a name="installation"/> Verify installation
CONTENT TBD

### Verify R installation
CONTENT TBD

### Verify PL/R installation
CONTENT TBD

## <a name="parallelization"/> Verify parallelization
Congratulations, you've just parellelized your first PL/R algorithm in GPDB. Or have you?? In this section we will describe 3 sanity check to ensure that your code is actually running in parallel.

### Writing temporary files
The simplest way to verify that your PL/R code is running on multiple segments is to write a temporary file from within the PL/R function. You can then log into each of the segments and inspect the temporary file. This method should only be used during debugging, as writing to disk will add unecessary overhead to query processing.  

In the example PL/R function below we add a system call to the Unix 'touch' function which updates the access and modification time a file to the current time. The sample PL/R function takes a file path as an argument, indicating where to write the file. Ensure that the path (but not the file) exists, or else the file may not be written.

```SQL
    DROP FUNCTION IF EXISTS my_plr_func( character );
    CREATE OR REPLACE FUNCTION my_plr_func( character ) 
    RETURNS BOOL AS 
    $$
        path = ifelse( arg1 == '', '/home/gpadmin/plrtest/weRhere', arg1 )
        system( paste( "touch", path ) )

        return TRUE
    $$
    LANGUAGE 'plr';

    select my_plr_func( '' ) from sample_model_data;
```

After running the sample code, log into the segments and note that the file specified in the path exists with an appropriate timestamp. Also note that if you remove the `FROM` clause (`select my_plr_func( '' );`) that the function will only run on the master node (`mdw`) and not on any of the segments. You can verify this using the same method described.

```
    [gpadmin@mdw ~]$ gpssh -f all_hosts
    => ls -la /home/gpadmin/weRhere
    [sdw16] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [sdw14] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [sdw15] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [sdw12] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [sdw13] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [sdw10] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [sdw11] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw9] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw4] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw5] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw6] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw7] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw1] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw2] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw3] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [ sdw8] -rw------- 1 gpadmin gpadmin 0 Feb 26 09:33 /home/gpadmin/weRhere
    [  mdw] ls: /home/gpadmin/weRhere: No such file or directory
    [ smdw] ls: /home/gpadmin/weRhere: No such file or directory
```

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

### Command center

## <a name="packages"/> R packages

R packages are the special sauce of R. This section explains how to check whether a package is installed and how to install new packages.

### Check R package installation
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

And it will return TRUE if the package could be loaded and FALSE if it couldn't. However, this only works on the node that you are currently logged on to.

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

`result_nodes` is a table that contains for every id, the host that it is stored on as hostname, and the result of R_test_require as result. Since we only want to know for every host once, we group by hostname like this:

```SQL
select hostname,bool_and(result) as host_result from result_nodes group by hostname order by hostname;
```

For a hostname where `R_test_require` returned true for all ids, the value in the column `host_result` will be true. If on a certain host the package couldn't be loaded, `host_result` will be false.

### Installing R packages
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
R CMD INSTALL lattice_0.19-33.tar.gz Matrix_1.0-1.tar.gz abind_1.4-0.tar.gz coda_0.14-7.tar.gz R2WinBUGS_2.1-18.tar.gz lme4_0.999375-42.tar.gz MASS_7.3-17.tar.gz arm_1.5-03.tar.gz -l $R_HOME/library
```

Check that the newly installed package is listed under the `$R_HOME/library` directory on all the segments (convenient to use `gpssh` here as well). If you do not see it in that directory:
1. Search for the directory (the name of the package) and determine which path it has installed to
2. Copy over the contents of this directory to the `$R_HOME/library` directory

### Package versions
Sometimes the current version of a package has dependencies on an earlier version of R. If this happens, you might get an error message like:

```
In getDependencies(pkgs, dependencies, available, lib) :
  package ‘matrix’ is not available (for R version 2.13.0)
```

Fortunately, there are older versions of most packages available in the CRAN archive. One heuristic we’ve found useful is to look at the release date of the R version installed on the machine. At the time of writing, it is v2.13 on our analytics DCA, which was released on 13-Apr-2011 (http://cran.r-project.org/src/base/R-2/). Armed with this date, go to the archive folder for the package you are installing and find the version that was released immediately prior to that date. For instance, the v1.5.3 of the package `glmnet` was released on 01-Mar-2011 and should be compatible with R v2.13 (http://cran.r-project.org/src/contrib/Archive/glmnet/ )

## <a name="packages"/> Notes on permissions
R is an untrusted language [untrusted]. Only superusers can create functions in untrusted languages. A discussion as to whether granting super user privileges on the database is acceptable needs to be an explicit step in selecting PL/R for your analytics project. 

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

[untrusted] http://www.postgresql.org/docs/current/interactive/catalog-pg-language.html

## <a name="packages"/> Best practices
CONTENT TBD

### Data preparation
CONTENT TBD

### Return types
CONTENT TBD

### UDA & UDF
CONTENT TBD

### RPostgreSQL
CONTENT TBD

## <a name="memory"/> Memory limitations
CONTENT TBD

## <a name="persistence"/> Persisting R models in database
CONTENT TBD

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

If you're using the GitHub for Mac, simply sync your repository and you'll see the new branch.

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