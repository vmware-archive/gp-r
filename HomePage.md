Topics covered
==============
* [Overview](#overview)
* [PL/R on Pivotal Greenplum Database](#plr)
  * [Getting Started](#plr_gettingstarted)
       * [PL/R Architecture](#plr_arch)
       * [PL/R Installation](#installation)
       * [Note on Permissions](#permissions)
  * [Leveraging R Packages](#packages)
       * [Checking R Package Availability](#plr_packages_check)
       * [Installing R Packages](#plr_packages_install)
       * [Note on R Package Versions & Dependencies](#plr_packages_versions)
  * [Usage & Best Practices](#bestpractices)
       * [Make a Plan](#makeplan)
       * [Data Preparation](#dataprep)
       * [Return types](#returntypes)
       * [PL/R UDF Definition](#udf)
       * [PL/R Execution](#execution)
       * [Persisting R Models in the Database](#persistence)
       * [Verify Parallelization](#parallelization)
             * [Option 1: Via Segment Hostnames](#plr_parallelization_hostnames)
             * [Option 2: Via Timing](#plr_parallelization_timing)
             * [Option 3: Via Pivotal Command Center](#plr_parallelization_cc)
  * [More Details](#plr_details)
       * [Data Types](#datatypes)
             * [PL/R Input Conversion: SQL Data Types → R Data Types](#plr_datatypes_input)
             * [PL/R Output Conversion: R Data Types → SQL Data Types](#plr_datatypes_output)
       * [Memory Limits](#memory)
       * [Performance Testing](#performance)
* [RPostgreSQL on Pivotal Greenplum Database](#rpostgresql)
  * [Introduction](#rpostgresql)
  * [Local Development](#rpostgresql_local)
  * [Plotting](#plotting)
  * [Caveats Around Usage Within PL/R](#rpostgresql_plrcaveats)
* [PivotalR on Pivotal Greenplum Database & PivotalHD HAWQ](#pivotalr)
  * [Introduction](#pivotalr)
  * [Design & Features](#pivotalr_design)
  * [Demo](#pivotalr_demo)
  * [Download & Installation](#pivotalr_install)


  
# <a name="overview"/> Overview 
In a traditional analytics workflow using R, data are loaded from a data source, modeled or visualized, and the model scoring results are pushed back to the data source. Such an approach works well when (i) the amount of data can be loaded into memory, and (ii) the transfer of large amounts of data is inexpensive and/or fast. Here we explore the situation involving large data sets where these two assumptions are violated. 

The Pivotal Greenplum database (GPDB) and PivotalHD w/ HAWQ offers several alternatives to interact with R using the in-database/in-Hadoop analytics paradigm. There are many ways to use R with the Pivotal platform. In this guide, we will outline the most common practices and provide code examples to help get you started.

Official documentation can be found here:
* [GPDB Product Page](http://www.pivotal.io/big-data/pivotal-greenplum-database)
* [GPDB Documentation](http://gpdb.docs.pivotal.io/index.html)
* [GPDB Installation guide](http://gpdb.docs.pivotal.io/4320/pdf/GPDB43InstallGuide.pdf)
* [GPDB Administrator guide](http://gpdb.docs.pivotal.io/4320/pdf/GPDB43AdminGuide.pdf)

This documentation is intended as a guide for **practitioners** and **should not** be considered official documentation. The intention is to give pragmatic tips on how to use the Greenplum Database with the R statistical programming environment.  

## Getting Started with this Guide

This guide contains code examples interspersed with explanations in natural language. You are encouraged to follow along with the examples, most of which will use the `abalone` [dataset](http://archive.ics.uci.edu/ml/datasets/Abalone) from the UC Irvine [Machine Learning Repository](http://archive.ics.uci.edu/ml/index.html).

To get started, download the data onto the file system of the GPDB host machine, and note the path: 
```
wget http://archive.ics.uci.edu/ml/machine-learning-databases/abalone/abalone.data
pwd
```

Next, create a table in GPDB to store the abalone data. Note that `/path/to/data` is the path returned by `pwd` in the previous line of code. 

```
DROP TABLE IF EXISTS abalone;
CREATE TABLE abalone (sex text, length float8, diameter float8, height float8, whole_weight float8, shucked_weight float8, viscera_weight float8, shell_weight float8, rings float8) 
DISTRIBUTED RANDOMLY;
COPY abalone FROM '/path/to/data/abalone.data' WITH CSV;
```

You should now have a table in the `public` schema of your database containing 4177 rows.

```
user# select count(*) from abalone;
 count 
-------
  4177
(1 row)
```

# <a name="plr"/> PL/R on Pivotal Greenplum Database

## <a name="plr_gettingstarted"/> Getting Started

### <a name="plr_arch"/> PL/R Architecture

![alt text](https://github.com/zimmeee/gp-r/blob/master/figures/PLR_GPDB_Architecture.png?raw=true "Distributed PL/R architecture on GPDB")

PL/R provides a connection from the database to R -- which is running on every segment of the Greenplum instance -- to allow you to write procedural functions in R. In this setup R is not a client application that runs on the desktop like pgadmin. It runs on each segment of the server.

### <a name="installation"/> Installation


#### Install and verify PL/R

Greenplum Engineering ships our own version of PL/R as a gppkg. You will not be able to download the source from Joe Conway's website
and compile it against the postgres headers supplied by Greenplum. Although Greenplum is based on Postgres 8.2, the source codes have diverged enough that your compilation of PL/R source (for Postgres 8.2) with Greenplum supplied postgres headers will not be successful.
Please contact support to obtain the gppkg for PL/R for your installation (internally, it can also be downloaded from SUBSCRIBENET). Once obtained, the gppkg for PL/R can be installed by following the steps below:

Gppkg command can be used to install PL/R on all segments.

```
gppkg --install plr-1.0-rhel5-x86_64.gppkg
```

This will install both PL/R and R as well.
You will find a folder `/usr/local/greenplum-db/ext/R-2.13/` upon the successful installation of the previous command.

You should see a trace like the following for each segment

```
bash-4.1$ gppkg --install plr-1.0-rhel5-x86_64.gppkg
20130524:10:56:17:007456 gppkg:agni_centos:gpadmin-[INFO]:-Starting gppkg with args: --install plr-1.0-rhel5-x86_64.gppkg
20130524:10:56:18:007456 gppkg:agni_centos:gpadmin-[INFO]:-Installing package plr-1.0-rhel5-x86_64.gppkg
20130524:10:56:18:007456 gppkg:agni_centos:gpadmin-[INFO]:-Validating rpm installation cmdStr='rpm --test -i /usr/local/greenplum-db-4.2.2.4/.tmp/plr-1.0-1.x86_64.rpm /usr/local/greenplum-db-4.2.2.4/.tmp/R-2.13.0-1.x86_64.rpm --dbpath /usr/local/greenplum-db-4.2.2.4/share/packages/database --prefix /usr/local/greenplum-db-4.2.2.4'
20130524:10:56:18:007456 gppkg:agni_centos:gpadmin-[INFO]:-Installing plr-1.0-rhel5-x86_64.gppkg locally
20130524:10:56:19:007456 gppkg:agni_centos:gpadmin-[INFO]:-Validating rpm installation cmdStr='rpm --test -i /usr/local/greenplum-db-4.2.2.4/.tmp/plr-1.0-1.x86_64.rpm /usr/local/greenplum-db-4.2.2.4/.tmp/R-2.13.0-1.x86_64.rpm --dbpath /usr/local/greenplum-db-4.2.2.4/share/packages/database --prefix /usr/local/greenplum-db-4.2.2.4'
20130524:10:56:19:007456 gppkg:agni_centos:gpadmin-[INFO]:-Installing rpms cmdStr='rpm -i /usr/local/greenplum-db-4.2.2.4/.tmp/plr-1.0-1.x86_64.rpm /usr/local/greenplum-db-4.2.2.4/.tmp/R-2.13.0-1.x86_64.rpm --dbpath /usr/local/greenplum-db-4.2.2.4/share/packages/database --prefix=/usr/local/greenplum-db-4.2.2.4'
20130524:10:56:20:007456 gppkg:agni_centos:gpadmin-[INFO]:-Completed local installation of plr-1.0-rhel5-x86_64.gppkg.
20130524:10:56:20:007456 gppkg:agni_centos:gpadmin-[INFO]:-Please source your $GPHOME/greenplum_path.sh file and restart the database.
You can enable PL/R by running createlang plr -d mydatabase.
20130524:10:56:20:007456 gppkg:agni_centos:gpadmin-[INFO]:-plr-1.0-rhel5-x86_64.gppkg successfully installed.
```

The installation can be verified by checking for the existence of the PL/R shared object in `/usr/local/greenplum-db/lib/postgresql/plr.so`

Now you'll have to source /usr/local/greenplum-db/greenplum_path.sh and restart GPDB for changes to the `LD_LIBRARY_PATH` environment variable to take effect.
Following the installation you'll see that the environment variable `R_HOME` has been set on all segments.
```
[gpadmin@mdw ~]$ echo $R_HOME
/usr/local/greenplum-db/./ext/R-2.13.0/lib64/R
[gpadmin@mdw ~]$ 
```

You can then install PL/R on your database by running

```
CREATE LANGUAGE PLR;
```

You may also install it on the template1 database to ensure every newly created database automatically has PL/R installed in it.


### <a name="permissions"/> Note on Permissions
R is an [untrusted language](http://www.postgresql.org/docs/current/interactive/catalog-pg-language.html). Only superusers can create functions in untrusted languages. A discussion as to whether granting super user privileges on the database is acceptable needs to be an explicit step in selecting PL/R for your analytics project. 

This is what happens when you try to create a PL/R function when you aren't a superuser:

``` 
ERROR:  permission denied for language plr

********** Error **********

ERROR: permission denied for language plr
SQL state: 42501
```

You do not need superuser privileges to EXECUTE a PL/R function, only to CREATE a PL/R function. Thus, non-superusers *can run* a PL/R function that was created by a superuser. In the GP Admin Guide there is a section entitled 'Managing Object Privileges' which outlines how to grant privileges to other roles for executing untrusted languages. 

GRANT USAGE privilege to the account 
http://lists.pgfoundry.org/pipermail/plr-general/2010-August/000441.html

## <a name="packages"/> Leveraging R Packages
The trick to installing R packages in a distributed Greenplum environment is that each segment has it's own R instance running and thus each segment needs its own version of all of the required packages. At a high-level, the steps for installing R packages on a Greenplum instance are:

1. Get the package tars from CRAN (`wget`)
2. Copy the tar to all the segments on the DCA (`gpscp`)
3. Install the package (`gpssh`, then `R CMD INSTALL`)


Note that any time you install a new R library/package using:

```
R CMD INSTALL <package name>
```

The resulting shared object (.so file) of the library
should be generated in `/usr/local/greenplum-db/ext/R-2.13.0/lib64/R/library/<library_name>`

### <a name="plr_packages_check"/> Checking R Package Availability

R packages are the special sauce of R. This section explains how to check whether a package is installed and how to install new packages. The simplest way to check if the requires R packages are available for PL/R is to `gpssh` into all the nodes and test if you are able to find the version of the required package. All the nodes
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

If the package is unavailable, the above code will error out. In the snippet below, we check for the version of the `HMM` package
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

If you do not have access to SSH into the GPDB or you prefer to only deal with UDFs to tell you if a PL/R package is present or absent, then you can write UDFs like the following:

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

### <a name="plr_packages_install"/> Installing R Packages

Before installing the packages for PL/R ensure that you are referring to the right R binary in your PATH and also ensure that the environment variable `R_HOME` is referring to the right location where you installed R. These paths should be identical on all master and segment nodes.

Some users have a separate stand-alone installation of R on just the master node. If this is the case with your installation, ensure that this does not conflict with installation you need for PL/R to run on multiple segments.

For a given R package, identify all dependent R packages and the package URLs.  This can be found by selecting the given package from the following navigation page: 
`http://cran.r-project.org/web/packages/available_packages_by_name.html`

From the page for the `arm` library, it can be seen that this library requires the following R libraries: `Matrix`, `lattice`, `lme4`, `R2WinBUGS`, `coda`, `abind`, `foreign`, `MASS`

From the command line, use wget to download the required packages' `tar.gz` files to the master node:

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

Using `gpscp` and the hostname file, copy the `tar.gz` files to the same directory on all nodes of the Greenplum cluster.  Note that this may require root access. (note: location and name of host file may be different. On our DCA its /home/gpadmin/all_hosts)

```
gpscp -f /home/gpadmin/all_hosts lattice_0.19-33.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/all_hosts Matrix_1.0-1.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/all_hosts abind_1.4-0.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/all_hosts coda_0.14-7.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/all_hosts R2WinBUGS_2.1-18.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/all_hosts lme4_0.999375-42.tar.gz =:/home/gpadmin 
gpscp -f /home/gpadmin/all_hosts MASS_7.3-17.tar.gz =:/home/gpadmin
gpscp -f /home/gpadmin/all_hosts arm_1.5-03.tar.gz =:/home/gpadmin
```

`gpssh` into all segments (`gpssh -f /home/gpadmin/all_hosts`).  Install the packages from the command prompt using the `R CMD INSTALL` command.  Note that this may require root access 

```
R CMD INSTALL lattice_0.19-33.tar.gz Matrix_1.0-1.tar.gz abind_1.4-0.tar.gz coda_0.14-7.tar.gz R2WinBUGS_2.1-18.tar.gz lme4_0.999375-42.tar.gz MASS_7.3-17.tar.gz arm_1.5-03.tar.gz
```

Check that the newly installed package is listed under the `$R_HOME/library` directory on all the segments (convenient to use `gpssh` here as well).

### <a name="plr_packages_versions"/> Note on R Package Versions & Dependencies
Sometimes the current version of a package has dependencies on an earlier version of R. If this happens, you might get an error message like:

```
In getDependencies(pkgs, dependencies, available, lib) :
  package ‘matrix’ is not available (for R version 2.13.0)
```

Fortunately, there are older versions of most packages available in the CRAN archive. One heuristic we’ve found useful is to look at the release date of the R version installed on the machine. At the time of writing, it is v2.13 on our analytics DCA, which was released on 13-Apr-2011 (http://cran.r-project.org/src/base/R-2/). Armed with this date, go to the archive folder for the package you are installing and find the version that was released immediately prior to that date. For instance, the v1.5.3 of the package `glmnet` was released on 01-Mar-2011 and should be compatible with R v2.13 (http://cran.r-project.org/src/contrib/Archive/glmnet/ ) and download that version. This manual heuristic works reasonably well for finding compatible package versions. 

## <a name="bestpractices"/> Usage & Best Practices
Here we outline workflows that have worked well for us in past experiences using R on Greenplum.  

One overarching theme for PL/R on Greenplum is that it is best suited in scenarios where the problem that you want to solve is one that is embarrassingly parallelizable. A simple way to think about PL/R is that it is provides functionality akin to MapReduce or R’s apply family of functions – with the added bonus of leveraging Greenplum native architecture to execute each mapper. In other words, it provides a nice framework for you to run parallelized `for` loops containing R jobs in Greenplum.  We focus our description of best practices around this theme.

  * [Make a plan](#makeplan)
  * [Data prep](#dataprep)
  * [Return types](#returntypes)
  * [PL/R UDF Definition](#udf)
  * [PL/R Execution](#execution)
  * [Persisting R Models in the Database](#persistence)
  * [Verifying Parallelization](#parallelization)

### <a name="makeplan"/> Make a Plan
Before doing anything, ask yourself whether the problem you are solving is explicitly parallelizable.  If so, identify what you’d like to parallelize by.  In other words, what is the index of your for loop?  This will play a large role in determining how you will prepare your data and build your PL/R function.

Using the abalone data as an example, let’s suppose you were interested in building a separate, completely independent model for each sex of abalone in the dataset.  Under this scenario, it’s clear that it would then make sense to parallelize by the abalone’s sex.  

### <a name="dataprep"/> Data Preparation
It’s often good practice to build another version of your table, dimensioned by the field by which you’d like to parallelize.  Let’s call this field the parallelization index for shorthand.  You essentially want to build a table where each row contains all the data for each value of the parallelization index.  This is done by array aggregation.  Using the SQL `array_agg()` function, aggregate all of the records for each unique value of the parallelization index into a single row.  

An example will make this more clear.  Let’s take a look at our raw abalone table:
```SQL
SELECT * FROM abalone LIMIT 3;
 sex | length | diameter | height | whole_weight | shucked_weight | viscera_weight | shell_weight | rings 
-----+--------+----------+--------+--------------+----------------+----------------+--------------+-------
 M   |  0.405 |     0.31 |    0.1 |        0.385 |          0.173 |         0.0915 |         0.11 |     7
 M   |  0.425 |     0.35 |  0.105 |        0.393 |           0.13 |          0.063 |        0.165 |     9
 I   |  0.315 |    0.245 |  0.085 |       0.1435 |          0.053 |         0.0475 |         0.05 |     8
(3 rows)
```
Let’s suppose that the end goal is to build a separate regression model for each sex with shucked_weight as the response variable and rings, diameter as explanatory variables.  Thinking ahead to this end goal, you would then create another version of the data table by:

1. Array aggregating each variable of interest,
2. Grouping by the parallelization index, and
3. Distributing by the parallelization index

To continue our example:

```SQL
DROP TABLE IF EXISTS abalone_array;
CREATE TABLE abalone_array AS SELECT 
sex::text
, array_agg(shucked_weight::float8) as s_weight
, array_agg(rings::float8) as rings
, array_agg(diameter::float8) as diameter 
FROM abalone 
GROUP BY sex 
DISTRIBUTED BY (sex);
```
The raw table is array aggregated into a table with rows equal to the number of unique values of the parallelization index.  For this specific example, there are three unique values of sex in the abalone data, and thus there are three rows in the abalone_array table.   

### <a name="returntypes"/> Return Types
As described in the Data Types section, it’s often difficult to read SQL arrays, and it's not possible to have SQL arrays containing both text and numeric entries.  For this reason, our best practice is to use custom composite types as return types for PL/R functions in Greenplum.  

It’s useful to think ahead and identify what the final output of your PL/R function will be.  In the case of our example, since we are running regressions, let’s suppose we want to return information that looks a lot like R’s `summary.lm()` function.  In particular, we are interested in getting back a table with each explanatory variable’s name, the coefficient estimate, standard error, t-statistic, and p-value.  With this in mind, we build a custom composite type as a template for the output we intend to get back from our PL/R function.  
```SQL
DROP TYPE IF EXISTS lm_abalone_type CASCADE;
CREATE TYPE lm_abalone_type AS (
Variable text, Coef_Est float, Std_Error float, T_Stat float, P_Value float); 
```

### <a name="udf"/> PL/R UDF Definition
Now that we’ve defined the structure of our input and output values, we can go ahead and tell Greenplum and R what we want to do with this data.  We are now ready to define our PL/R function. 

A couple of helpful rules to follow here:
* Each argument of the PL/R function and its specified data type should correspond to a column that exists in the array aggregated table that was created in the Data Prep step
* The return data type of the PL/R function should be a SETOF the composite type that was created in the Return Types step

Continuing our example using the abalone data, we define the following PL/R function:

```SQL
CREATE OR REPLACE FUNCTION lm_abalone_plr(s_weight float8[], rings float8[], diameter float8[]) 
RETURNS SETOF lm_abalone_type AS 
$$ 
    m1<- lm(s_weight~rings+diameter)
    m1_s<- summary(m1)$coef
    temp_m1<- data.frame(rownames(m1_s), m1_s)
    return(temp_m1)
$$ 
LANGUAGE 'plr';
```

### <a name="execution"/> PL/R Execution
We then execute the PL/R function by specifying the parallelization index and the function call in the SELECT statement.  

To conclude our example, we run the following SELECT statement to run 3 separate regression models; one model for each sex.  Under this scenario, execution is parallelized by the abalone’s sex:
```SQL
SELECT  sex, (lm_abalone_plr(s_weight,rings,diameter)).* FROM abalone_array;
 sex |  variable   |       coef_est       |      std_error       |       t_stat       |        p_value        
 -----+-------------+----------------------+----------------------+--------------------+----------------------- 
 F   | (Intercept) |   -0.617050922097655 |   0.0169416168113397 |   -36.422198009144 | 6.03016903934925e-201 
 F   | rings       | -0.00956233525043721 | 0.000835808125948978 |  -11.4408258947951 |  5.96598342834597e-29 
 F   | diameter    |     2.57219713416591 |   0.0365667203043869 |    70.342571407951 |                     0 
 M   | (Intercept) |   -0.534293488484019 |   0.0148876715438078 |  -35.8883178549332 | 5.42293200035969e-205 
 M   | rings       |  -0.0101856670676353 |  0.00096233015174409 |  -10.5843790191704 |  2.59455668009866e-25 
 M   | diameter    |     2.45006792350753 |   0.0345072752341834 |   71.0014890158715 |                     0
 I   | (Intercept) |   -0.236131314300337 |  0.00601596875673268 |  -39.2507547576729 | 6.73787958361764e-225
 I   | rings       | -0.00046870969168018 | 0.000850383676525165 | -0.551174375307179 |     0.581606099530735
 I   | diameter    |     1.31967087153234 |   0.0242402717496186 |   54.4412573078149 |                     0
(9 rows)

```

### <a name="persistence"/> Persisting R Models in the Database
One benefit of using PL/R on an MPP database like Greenplum is the ability to perform scoring in parallel across all the segments.
If you've trained a GLM model for instance, you could save a serialized version of this model in a database table and de-serialize it when needed and use it for scoring.

Typically the models are built once or are trained periodically depending on what the application may be, but the scoring may have to happen in real-time as new data becomes available.
If the data to be scored is stored in a table distributed across the segments on GPDB, then by ensuring the trained models are also distributed across the same segments, we can achieve parallel scoring through PL/R.

The simplest approach would be to serialize the entire model into a byte array and store it in a table, although not all parameters of the R model are required for scoring. For example, for linear or logistic regression we only need the coefficients of the features to perform scoring. Advanced users should be able to extract only the relevant parameters from the model and serialize them into a byte array on a table. This will improve scoring speed as the segment nodes won't have to de-serialize large byte arrays. Another optimization that will speed up scoring will be to pre-load the models into memory on the segment nodes - so that models are not de-serialized for every PL/R function call. In both these cases the user will have to write additional logic beside the scoring itself, for the optimization.

In the sample code shown below we demonstrate some of these optimizations. This guide is work in progress and in the upcoming versions we will include more examples to optimize the scoring function.

First we'll define a custom record type to hold the results from a GLM model. This is equivalent to the summary() function in R.

```SQL 
	DROP TYPE IF EXISTS gpdemo.glm_result_type CASCADE;
	CREATE TYPE gpdemo.glm_result_type 
	AS 
	(
		params text, 
		estimate float, 
		std_Error float, 
		z_value float, 
		pr_gr_z float
	);
```

Here is a PL/R function that demonstrates how a trained GLM model can be serialized as a byte array. The sample table `patient_history_train` is included in the data folder of this repository.

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
	     #The model is serialized and returned as a bytearray
	     return (serialize(mdl,NULL))
	$$
	LANGUAGE 'plr';
```

Here is a PL/R function to read a serialized PL/R model examine it's parameters.

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

The function can be invoked like so:

```SQL
	select (t).params, 
	       (t).estimate,
	       (t).std_Error, 
	       (t).z_value float, 
	       (t).pr_gr_z 
	from 
	(
	       -- The column 't' is of glm_result_type that we defined in step 3s.
	       select mdl_load_demo(model) as t 
	       from mdls
	) q ;
```

Here is the PL/R function which demonstrate parallel scoring using the GLM model we trained in the example above.

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

You can also score a whole array:
```SQL
	DROP FUNCTION IF EXISTS gpdemo.mdl_score_demo( bytea, 
							integer[],
							text[],
							text[],
							text[],
							double precision[],
							integer[],
							integer[],
							integer[],
							integer[],
							integer[],
							integer[],
							integer[] 
						      );
	CREATE FUNCTION gpdemo.mdl_score_demo( mdl bytea, 
						age integer[],
						gender text[],
						race text[],
						marital_status text[],
						bmi double precision[],
						med_cond1 integer[],
						med_cond2 integer[],
						med_cond3 integer[],
						med_cond4 integer[],
						med_cond5 integer[],
						med_cond6 integer[],
						med_cond7 integer[] 
					      ) 
	RETURNS numeric[]
    IMMUTABLE
    AS
	$$
	    gp_plr_mdl_score <- unserialize(mdl)

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
			from gpdemo.plr_mdls mdls, 
			     gpdemo.patient_history_test test 
		) q1
	) q2 group by cnt;
```

### <a name="parallelization"/> Verify Parallelization
Congratulations, you've just parallelized your first PL/R algorithm in GPDB. Or have you? In this section we will describe three sanity checks to ensure that your code is actually running in parallel. 


#### <a name="plr_parallelization_hostnames"/> Option 1: Via Segment Hostnames 
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

The function returns the hostname of the segment node on which it is executing. By invoking the function for rows from a table that is distributed across all segments, we can verify if we indeed
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

#### <a name="plr_parallelization_timing"/> Option 2: Via Timing
An alternative way to verify whether your code is running in parallel is to do timed performance testing. This method is laborious, but can be helpful in precisely communicating the speedup achieved through parallelization to a business partner or customer. Using the abalone dataset, we show how to compare the timing results from an implementation that builds models sequentially with a version that builds models in parallel. 

First we create a PL/R function which builds a linear regression to predict the age of an abalone (determined by counting the number of rings) from physical measurements. The function returns the coefficients for each of the linear predictors. 

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

Next we convert the dataset to an array representation (as described in [Data Preparation](#dataprep)) and store the results in a new table called `abalone_array`.

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

The function accepts a single argument, which specifies the number of iterations. For this example we set that value to 64 and expect that the running time will be roughly the length of time it took to build a single model multiplied by the number of iterations: 47 * 64 = 3008 ms.

```SQL
    SELECT IterativePLRModels( 64 );
    -----------
    (64 rows)

    Time: 2875.609 ms
```

Pretty darn close!

Next let's construct the models in parallel. In order to do this we must replicate the abalone data and distribute it across the GPDB segments. The PGSQL function below creates a new table called `abalone_array_replicates` that contains copies of the abalone dataset indexed by a `distkey` and distributed randomly across the segments. 

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

Of course, parallelization aint perfect! There is overhead associated with parallel processing. However, the contribution of the overhead to the overall running time of an algorithm shrinks as the size of the data increase. Additionally, since the distribution function is `random` data are not necessarily *uniformly* distributed across segments. You can see how the data are distributed by interrogating the database like this:

```SQL
SELECT gp_segment_id, count(*)
FROM abalone_array_replicates
GROUP BY gp_segment_id
ORDER BY gp_segment_id;
```

If you plot the results in R:

```splus
barplot( segment_distribution, xlab='Segment ID', ylab='Number of rows', main = 'Row distribution w/ sequential dist key' )
```

You will get a plot that looks something like the one below. Note that certain segments (64, 61) have 3 models to build, while others only have 1. The overall running time of the algorithm is bounded by the running time of the slowest node - a good reminder of why it is important to choose your distribution key wisely!

![alt text](https://github.com/zimmeee/gp-r/blob/master/figures/RowDistAcrossSegments.png?raw=true "Row distribution across segments")

#### <a name="plr_parallelization_cc"/> Option 3: Via Pivotal Command Center 
A heuristic, visual option to verify parallelism is via the Pivotal Command Center.  You would want to start by logging into Pivotal Command Center, and navigating to the 'Realtime (By Server)' menu under the 'System Metrics' tab.  Below is an example of how this page should look if your database is idle:

![alt text](https://github.com/wjjung317/gp-r/blob/master/figures/commandcenter_idle.png?raw=true "Snapshot of Pivotal Command Center When DB is Idle")

Suppose that you have now successfully implemented a parallelized PL/R function.  While the function is executing, check back on that same page on Pivotal Command Center - it should look like the following.  Note that the CPU panel shows activity for multiple database segments - if the function was not successfully parallelized, then only a single segment would show CPU activity.

![alt text](https://github.com/wjjung317/gp-r/blob/master/figures/commandcenter_parallelized.png?raw=true "Snapshot of Pivotal Command Center When DB is Executing a Parallelized PL/R Function")



## <a name="plr_details"/> More Details

### <a name="datatypes"/> Data Types
At its core, a function takes in input, does something with this input, and produces output.  PL/R functions in Greenplum:

1.	Take SQL data types as input
2.	Converts SQL data types to R data types
3.	Outputs results as R data types
4.	Converts the R data type output as SQL data types

(1) and (3) are fairly straightforward.  We personally found (2) and (4) a little less straightforward, and would like to devote some space to go into these two pieces in more detail.  

The purpose of this section is really to just help users be aware of default data type conversions, and keep them in mind when doing code development and debugging.

It is our subjective view that being familiar with the treatment of multi-element data types is generally more useful for day-to-day data science.  We focus on PL/R’s default treatment of multi-element numeric data types rather than scalars or text values.  Material on scalars and text will soon follow.  

#### <a name="plr_datatypes_input"/> PL/R Input Conversion: SQL Data Types → R Data Types

We will describe how SQL data types are converted into R data types via PL/R in this section.  

Let’s take a look at some examples.  We first define a PL/R function that simply returns a string of identifying the R data type:
```SQL
DROP FUNCTION IF EXISTS func_array(arg_array float8[]);
CREATE FUNCTION func_array(arg_array float8[]) 
RETURNS text AS 
$$ 
d<- arg_array
return(class(d))
$$
LANGUAGE 'plr';
```

You would think that 1D SQL arrays (i.e. a vector of values) should map to R vectors, but we see that 1D SQL arrays default-map to 1D R arrays:
```SQL
SELECT array[1,2,3,4];
   array   
-----------
 {1,2,3,4}
(1 row)

SELECT func_array(array[1,2,3,4]);
func_array 
------------
 array
(1 row)

```
Given the result for 1D SQL arrays, what are your bets on how 2D SQL arrays are mapped to R objects?  Turns out that 2D SQL arrays (i.e. a matrix) default-map to R matrices (not R 2D arrays):
```SQL
SELECT array[array[1,2], array[3,4]];
     array     
---------------
 {{1,2},{3,4}}
(1 row)
SELECT func_array(array[array[1,2],array[3,4]]);
 func_array 
------------
 matrix
(1 row)
```

And as one would expect, 3D SQL arrays map to an R array:
```SQL
SELECT array[array[array[1,2], array[3,4]],array[array[5,6], array[7,8]]];
             array             
-------------------------------
 {{{1,2},{3,4}},{{5,6},{7,8}}}
(1 row)
SELECT func_array(array[array[array[1,2], array[3,4]],array[array[5,6], array[7,8]]]);
func_array 
------------
 array
(1 row)
```

You can of course convert between data types in R, so if an R function that you’d like to use in your workflow expects data to be in a certain R class, just make appropriate conversions in your PL/R code:
```SQL
DROP FUNCTION IF EXISTS func_convert_example(arg_array float8[]);
CREATE FUNCTION func_convert_example(arg_array float8[]) 
RETURNS text AS 
$$ 
d<- arg_array
d<- as.data.frame(d)
return(class(d))
$$
LANGUAGE 'plr';

SELECT func_convert_example(array[array[1,2], array[3,4]]); 
func_convert_example 
----------------------
 data.frame
(1 row)
```

#### <a name="plr_datatypes_output"/> PL/R Output Conversion: R Data Types → SQL Data Types
For multi-element returns from a PL/R function, you generally have two options.  Multi-element return objects from PL/R can be expressed as:

1.	A SQL array (in all flavors: 1D,2D,3D), or 
2.	A SQL composite type

The quickest, “hands-free” approach is to just specify your return object as a SQL array.  Regardless of whether your R object is a vector, matrix, data.frame, or array, you will be able to recover the information contained in the R object by specifying a SQL array as your RETURN data type for a given PL/R function.

* Vectors, a single column of a matrix or data.frame, and a 1D R array are returned as a 1D SQL array
* A matrix, a data.frame, and a 2D R array are returned as a 2D SQL array
* A 3D R array is returned as a 3D SQL array

A couple of caveats here.  Arrays can be somewhat difficult to look at in SQL.  Also, there currently isn’t support for arrays of mixed type.  You can nominally set your return type to a text[], but this will find limited use in an analytics workflow.

A richer, more flexible approach is to use a SQL composite type as your RETURN data type for a given PL/R function.  Let’s suppose you wanted to return the equivalent of an R data frame in your PL/R function.  In other words, lets suppose you’d like to return a table where at least one of the columns contains text rather than numbers.  We allow for this return by first setting up a SQL composite type in Greenplum.  You can think of SQL composite types as a “template” or “skeleton” for SQL tables.  When setting up a type, it’s useful to think ahead and draw out the format of the output you intend to get back from your PL/R function.
```SQL
DROP TYPE IF EXISTS iris_type CASCADE;
CREATE TYPE iris_type AS (
sepal_length float8, sepal_width float8, petal_length float8, petal_width float8, specices text);
```
We can then return output from a PL/R function which follows the structure of the type you’ve created.  You just need to specify your return type as a SETOF your custom type:
```SQL
CREATE OR REPLACE FUNCTION iris_trivial ()  
RETURNS SETOF iris_type AS 
$$ 
data(iris)
d<- iris
return(d[c(1,51,100),])
$$
LANGUAGE 'plr';

SELECT * from iris_trivial();
sepal_length | sepal_width | petal_length | petal_width |  specices  
--------------+-------------+--------------+-------------+------------
          5.1 |         3.5 |          1.4 |         0.2 | setosa
            7 |         3.2 |          4.7 |         1.4 | versicolor
          5.7 |         2.8 |          4.1 |         1.3 | versicolor
(3 rows)
```

The data types for the individual columns are governed by those of the SQL composite defined:

```SQL
DROP TABLE IF EXISTS iris_trivial_table;
CREATE TABLE iris_trivial_table AS SELECT * FROM iris_trivial();
\d+ iris_trivial_table
                  Table "public.iris_trivial_table"
    Column    |       Type       | Modifiers | Storage  | Description 
--------------+------------------+-----------+----------+-------------
 sepal_length | double precision |           | plain    | 
 sepal_width  | double precision |           | plain    | 
 petal_length | double precision |           | plain    | 
 petal_width  | double precision |           | plain    | 
 specices     | text             |           | extended | 
```

We see that this is identical to the set of column data types of iris_type.

### <a name="memory"/> Memory Limits
When coding in PL/R there are a couple of memory management items to keep in mind.  

Recall that R is installed on each and every host of the Greenplum database - one corrollary is that each "mapper" job which you wish to execute in parallel via PL/R must fit in the memory of the R on each host.  

Given the heavy use of arrays in a PL/R workflow, another item to keep in mind is that the maximum memory limit for each cell (i.e. each record-column tuple) in Greenplum database is 1GB.  This is a theoretical upper bound and in practice, the maximum can be less than 1GB.  

### <a name="performance"/> Performance testing
CONTENT TBD



# <a name="rpostgresql"/> RPostgreSQL on Pivotal Greenplum Database
## Overview
The [RPostgreSQL package](http://cran.r-project.org/web/packages/RPostgreSQL/index.html) provides a database interface and PostgreSQL driver for R that is compatible with the Greenplum database. This connection can be used to query the database in the normal fashion from within R code. We have found this package to be helpful for prototyping, working with datasets that can fit in-memory, and building visualizations. Generally speaking, using the RPostgreSQL interface does not lend itself to parallelization.  

Using RPostgreSQL with a database includes the following 3 steps: 

1.      Create a database driver for PostgreSQL, 
2.      Connect to a specific database, and 
3.      Execute the query on GPDB and return results 

## <a name="rpostgresql_local"/> Local Development
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

## <a name="plotting"/> Plotting
It is probably best to do plotting on a single node (either the master or locally using the RPostgreSQL interface). In this context, plotting is no different from normal plotting in R. Of course, you likely have *a lot* of data which may obscure traditional visualization techniques. You may choose to experiment with packages like [bigviz](https://github.com/hadley/bigvis) which provides tools for exploratory data analysis of large datasets. 

## <a name="rpostgresql_plrcaveats"/> Caveats Around Usage Within PL/R 
RPostgreSQL can also be used from within a PL/R function and deployed on the host GPDB instance. This bypasses the PL/R pipe for data exchange in favor of the DBI driver used by RPostgreSQL. The primary benefit of using this interface over the standard PL/R interface is that datatype conversions happen automatically; one need not specify all of the columns and their datatypes to pass to the function ahead of time. Sensible conversions are done automatically, including conversion of strings to factors which can be helpful in downstream processes. 

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

GPDB is complaining because you are trying to access a table directly from a segment, which breaks the whole notion of coordination between the master node and its segments. Therefore, you cannot specify a `FROM` clause in your PL/R function when you make an RPostgreSQL call from within that function. 

#### Alternative
For the adventerous, the RPostgreSQL package provides more granular control over execution. An equivalent to dbGetQuery is to first submit the SQL to the database engine using dbSendQuery and then fetch the results: 

```splus
drv <- dbDriver( "PostgreSQL" )
con <- dbConnect( drv )
res <- dbSendQuery( con, "SELECT * FROM sample_model_data;" )
data <- fetch( res, n = -1 ) 
```

Note that the fetch function has a parameter, `n`, which sets the maximum number of records to retrieve. You probably always want to set this value to -1 to retrieve all of the records. I'm not sure why you would ever use this instead of the simpler dbGetQuery. 

# <a name="pivotalr"/> PivotalR on Pivotal Greenplum Database & PivotalHD HAWQ
## Introduction
[MADlib](http://madlib.net) is an open-source library for highly scalable in-database/in-Hadoop analytics, and it currently runs on Pivotal Greenplum Database, PivotalHD w/ HAWQ, and PostgreSQL.  MADlib provides implicitly parallelized SQL implementations of statistical & machine learning models that run directly inside the database. Examples of algorithms currently available in MADlib include linear regression, logistic regression, multinomial regression, elastic net, ARIMA, k-means clustering, naïve bayes, decision trees, random forests, support vector machines, Cox proportional hazards, conditional random fields, association rules, and latent dirichlet allocation.  

While end users benefit from MADlib’s high performance and scalability, its audience has previously been focused to those who are comfortable with modeling in SQL. [PivotalR](http://cran.r-project.org/web/packages/PivotalR/) is an R package that allows practitioners who know R but very little SQL to leverage the performance and scalability benefits of in-database/in-Hadoop processing.  

The debut release of PivotalR was shipped out in June 2013.  A quickstart guide to PivotalR is available [here](https://github.com/wjjung317/gp-r/blob/master/docs/PivotalR-quick-start%20v2.pdf).  There is active ongoing development of  PivotalR, and we encourage you to view or contribute to this work on its [GitHub Page](https://github.com/madlib-internal/PivotalR).

## <a name="pivotalr_design"/> Design & Features
![alt text](https://github.com/wjjung317/gp-r/blob/master/figures/PivotalR.png?raw=true "PivotalR Design")

At its core, an R function in PivotalR:

1. Translates R model formulas into corresponding SQL statements
2. Executes these statements on the database
3. Returns summarized model output to R 

This allows R users to leverage the scalability and performance of in-database analytics without leaving the R command line. All of the computational heavy lifting is executed in-database, while the end user benefits from a familiar R interface.  Compared with respective native R functions, we observe a dramatic increase in scalability and a decrease in running time, even after normalizing for hardware differences. Furthermore, data movement -- which can take hours for big data -- is eliminated via PivotalR.  

Key features include the following:

* All data stays in DB: R objects merely point to DB objects
* All model estimation and heavy lifting done in DB via MADlib 
* R → SQL translation done via PivotalR
* Only strings of SQL and model output transferred across RPostgreSQL -- trivial data transfer

## <a name="pivotalr_demo"/> Demo

We have put together a [video demo](http://www.youtube.com/watch?v=6cmyRCMY6j0) of the debut release of PivotalR.  We also provide the [deck](https://github.com/wjjung317/gp-r/blob/master/docs/PivotalR_Demo.pptx), [code](https://github.com/wjjung317/gp-r/blob/master/src/R/PivotalR_Demo.R), and [data](https://drive.google.com/file/d/0B76GEdSVCa8NUlZhQnFBaGgyTk0/view?usp=sharing) used in the demo. Note that the demo intends to highlight a selection of functionality in PivotalR - we encourage you to check out the [documentation](http://cran.r-project.org/web/packages/PivotalR/PivotalR.pdf) to explore more of its features.  

## <a name="pivotalr_install"/> Download & Installation

PivotalR is available for download and installation from [CRAN](http://cran.r-project.org/web/packages/PivotalR/) and its [GitHub Page](https://github.com/gopivotal/PivotalR).


# Authors and Contributors
This document is a project by Woo Jung (@wjjung317), Srivatsan 'Vatsan' Ramanujam (@vatsan) and Noah Zimmerman (@zimmeee), Alex Kagoshima (@alexkago) and Ronert Obst (@ronert).
