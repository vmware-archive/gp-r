abalone = read.csv( 'http://archive.ics.uci.edu/ml/machine-learning-databases/abalone/abalone.data',
					header=FALSE )

names(abalone) = c('sex', 'length', 'diameter', 'height', 'whole_weight', 
					'shucked_weight', 'viscera_weight', 'shell_weight', 'rings' )


m = lm(formula = rings ~ ., data = abalone)

coef( m )

# Plotting the distribution of rows across segments

# SQL to retrieve the gp_segment_id for each of the rows
SELECT distkey, gp_segment_id FROM abalone_array_replicates;

# Quick and dirty: In pgAdmin, select the gp_segment_id column
# from the query above and copy it to the clipboard
# then run the code below in R
x = readLines(pipe("pbpaste"))
y = table(x)
barplot( y[order( as.integer(rownames(y)) )], xlab='Segment ID', 
		 ylab='Number of rows', main = 'Row distribution across segments' )