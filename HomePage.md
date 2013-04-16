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

### Command center

## <a name="packages"/> Installing packages
CONTENT TBD

## <a name="packages"/> Notes on permissions
CONTENT TBD

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

### Designer Templates
We've crafted some handsome templates for you to use. Go ahead and continue to layouts to browse through them. You can easily go back to edit your page before publishing. After publishing your page, you can revisit the page generator and switch to another theme. Your Page content will be preserved if it remained markdown format.

```splus
m = lm(formula = rings ~ ., data = abalone)

x = readLines(pipe("pbpaste"))
y = table(x)
barplot( y[order( as.integer(rownames(y)) )], xlab='Segment ID', 
		 ylab='Number of rows', main = 'Row distribution across segments' )
```

### Rather Drive Stick?
If you prefer to not use the automatic generator, push a branch named `gh-pages` to your repository to create a page manually. In addition to supporting regular HTML content, GitHub Pages support Jekyll, a simple, blog aware static site generator written by our own Tom Preston-Werner. Jekyll makes it easy to create site-wide headers and footers without having to copy them across every page. It also offers intelligent blog support and other advanced templating features.

### Authors and Contributors
This document is a project by Woo Jung (@wjjung317), Srivatsan 'Vatsan' Ramanujam (@vatsan) and Noah Zimmerman (@zimmeee)