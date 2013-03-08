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
Here is some text

## Another header
With some text

### Welcome to GitHub Pages.
This automatic page generator is the easiest way to create beautiful pages for all of your projects. Author your page content here using GitHub Flavored Markdown, select a template crafted by a designer, and publish. After your page is generated, you can check out the new branch:

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
This document is a project by Woo Jung (@wjjung317) and Noah Zimmerman (@zimmeee)