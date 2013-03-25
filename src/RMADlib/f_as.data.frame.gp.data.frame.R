#Define function
as.data.frame.gp.data.frame <- 

function (x, size = 100) 
{
    if (!length(names(x))) 
        stop("There are no columns in gp.data.frame")
    tableName<- attr(x, "tableName")
    query <- paste("SELECT * FROM ", tableName , " LIMIT ", size)
  
    return(dbGetQuery(gpConnection, query))
}

#Try out function
gpConnect(host="10.110.122.107", dbname="airlines",user="gpadmin", password="changeme")
gdf<- gp.data.frame("use_r.census1")
gdf.sample100<- as.data.frame(gdf)
gdf.sample10<- as.data.frame(gdf, 10)
