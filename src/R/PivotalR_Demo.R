#Load PivotalR library and connect to DB 
library(PivotalR)
db.connect(dbname="pivotalr_demodb", user="wjung", password="wjung", host="10.110.122.107")
db.list()


# List all db objects, show example of deleting a table
db.objects()
delete()
db.objects()

# Create a db.data.frame R object, and have it point to a table in the database.  Note that a db.data.frame can be either a db.table or a db.Rquery object.
d1<- db.data.frame("census1_part1")
class(d1)
names(d1)
dim(d1)
preview(d1,10)
preview(d1[,1:4], 10)


# Get descriptive stats about the table
?summary
summary(d1)

# Do some data transformations and save final table in DB
class(d1)
d1$wage<- d1$earns/d1$hours
class(d1) # Note that it is now an Rquery object

names(d1)
preview(d1,10)

d1<- as.db.data.frame(d1, "census1_part1_final")
class(d1)


# Build linear regression model
?madlib.lm
names(d1)
m1<- madlib.lm(wage~professional+rooms, data=d1)
summary(m1)

names(d1[,5:16])
m1<- madlib.lm(wage~.-row_id, data=d1[,5:16])
summary(m1)


# You can also build a logistic regression model
?madlib.glm
m1<- madlib.glm(professional~wage, family="binomial", data=d1)
summary(m1)


# Suppose you want to bring in additional variables that live in a different DB table -- do DB joins directly from R
db.objects()
?merge

d2<- db.data.frame("census1_part2")
names(d2)
names(d1)
d<- merge(d1,d2, by="row_id")
names(d) # note that it automatically allows for duplicate columns to exist
class(d)
d<- as.db.data.frame(d, "census1_merged")
class(d)

m1<- madlib.lm(wage~professional+rooms+rentshouse+married, data=d)
summary(m1)


# Suppose we had reason to believe there were considerable differences in wage between states that are not explained by the explanatory variables
d_meanwage_bystate<- by(d1$wage, d1$h_state, mean)
preview(d_meanwage_bystate)


# Build a regression model with a different intercept term for each state (state=1 as baseline)
names(d)
preview(d,10) # need to as.factor() state -- PivotalR supports automated dummy coding!
m1_state<- madlib.lm(wage~as.factor(h_state_x)+professional+rooms+rentshouse+married, data=d)
summary(m1_state)


