----------------------------------------------------------------------------------------------------------------------------------
--                         PL/R exercise for "Data Science in Practice" course                                                  --
--                                 Decision Trees in PL/R                                                                       --
--                         Regunathan Radhakrishnan <rradhakrishnan@pivotal.io>                                                 --
----------------------------------------------------------------------------------------------------------------------------------

--Predict if a car purchased at auction is a lemon
--Given Purchase data for each car in an auction, the problem is to 
--predict whether the buy is good/bad
--https://www.kaggle.com/c/DontGetKicked/

----------------------------------------------------------------------------------------------------------------------------------
-- Feature Dictionary
----------------------------------------------------------------------------------------------------------------------------------
--Field Name              Definition
--RefID                   Unique (sequential) number assigned to vehicles
--IsBadBuy                Identifies if the kicked vehicle was an avoidable purchase 
--PurchDate               The Date the vehicle was Purchased at Auction
--Auction                 Auction provider at which the  vehicle was purchased
--VehYear                 The manufacturer's year of the vehicle
--VehicleAge              The Years elapsed since the manufacturer's year
--Make                    Vehicle Manufacturer 
--Model                   Vehicle Model
--Trim                    Vehicle Trim Level
--SubModel                Vehicle Submodel
--Color                   Vehicle Color
--Transmission            Vehicles transmission type (Automatic, Manual)
--WheelTypeID             The type id of the vehicle wheel
--WheelType               The vehicle wheel type description (Alloy, Covers)
--VehOdo                  The vehicles odometer reading
--Nationality             The Manufacturer's country
--Size                    The size category of the vehicle (Compact, SUV, etc.)
--TopThreeAmericanName            Identifies if the manufacturer is one of the top three American manufacturers
--MMRAcquisitionAuctionAveragePrice   Acquisition price for this vehicle in average condition at time of purchase 
--MMRAcquisitionAuctionCleanPrice     Acquisition price for this vehicle in the above Average condition at time of purchase
--MMRAcquisitionRetailAveragePrice    Acquisition price for this vehicle in the retail market in average condition at time of purchase
--MMRAcquisitonRetailCleanPrice       Acquisition price for this vehicle in the retail market in above average condition at time of purchase
--MMRCurrentAuctionAveragePrice       Acquisition price for this vehicle in average condition as of current day   
--MMRCurrentAuctionCleanPrice         Acquisition price for this vehicle in the above condition as of current day
--MMRCurrentRetailAveragePrice        Acquisition price for this vehicle in the retail market in average condition as of current day
--MMRCurrentRetailCleanPrice          Acquisition price for this vehicle in the retail market in above average condition as of current day
--PRIMEUNIT               Identifies if the vehicle would have a higher demand than a standard purchase
--AcquisitionType         Identifies how the vehicle was aquired (Auction buy, trade in, etc)
--AUCGUART                The level guarntee provided by auction for the vehicle (Green light - Guaranteed/arbitratable, 
--                        Yellow Light - caution/issue, red light - sold as is)
--KickDate                Date the vehicle was kicked back to the auction
--BYRNO                   Unique number assigned to the buyer that purchased the vehicle
--VNZIP                   Zipcode where the car was purchased
--VNST                    State where the the car was purchased
--VehBCost                Acquisition cost paid for the vehicle at time of purchase
--IsOnlineSale            Identifies if the vehicle was originally purchased online
--WarrantyCost            Warranty price (term=36month  and millage=36K) 
----------------------------------------------------------------------------------------------------------------------------------

---step 0: data loading
create schema trn_ex_dt;

drop table if exists trn_ex_dt.all_car_data;
create table trn_ex_dt.all_car_data
(
    refid int,
    isbadbuy int,
    purchdate timestamp,
    auction text,
    vehyear int,  
    vehicleage int,
    make text,
    model text, 
    trim text,
    submodel text,  
    color text,
    transmission text,
    wheeltypeid text, 
    wheeltype text,
    vehodo int, 
    nationality text,
    size text,
    topthreeamericanname text,
    mmracquisitionauctionaverageprice text,
    mmracquisitionauctioncleanprice text,
    mmracquisitionretailaverageprice text,
    mmracquisitonretailcleanprice text,
    mmrcurrentauctionaverageprice text,
    mmrcurrentauctioncleanprice text,
    mmrcurrentretailaverageprice text,
    mmrcurrentretailcleanprice text,
    primeunit text, 
    aucguart text,  
    byrno int,
    vnzip1 int, 
    vnst text,
    vehbcost float,
    isonlinesale int, 
    warrantycost int
) distributed by (refid);
--15120

copy trn_ex_dt.all_car_data from '/data/labs/PLX/data/lemon.csv' delimiter ',' csv header;


--step 1:data exploration & filtering

--Question 1: what is the distribution of VehicleAge for good cars and bad cars?
--Solution 1:
select 
     vehicleage,
     count(*) 
from 
    trn_ex_dt.all_car_data 
where
    isbadbuy = 0
group by 1 order by 1;

/*

select 
    vehicleage,
    (sum(is_bad_vehicle)*1.0/count(*)) as frac_bad_buy
from

(
    select 
         vehicleage,
         case when isbadbuy=1 then 1 else 0 end as is_bad_vehicle
    from 
        trn_ex_dt.all_car_data 
)q
group by 1
order by 1;


*/



select 
     vehicleage,
     count(*) 
from 
    trn_ex_dt.all_car_data 
where
    isbadbuy = 1
group by 1 order by 1;

--selecting records for which the price values are not NULL
drop table if exists trn_ex_dt.all_car_data_fil;
create table trn_ex_dt.all_car_data_fil as
(
    select
        refid,
        isbadbuy,
        purchdate,
        auction,
        vehyear,   
        vehicleage,
        make,
        model, 
        trim,
        submodel,  
        color,
        transmission,
        wheeltypeid,   
        wheeltype,
        vehodo,    
        nationality,
        size,
        topthreeamericanname,
        mmracquisitionauctionaverageprice::int,
        mmracquisitionauctioncleanprice::int,
        mmracquisitionretailaverageprice::int,
        mmracquisitonretailcleanprice::int,
        mmrcurrentauctionaverageprice::int,
        mmrcurrentauctioncleanprice::int,
        mmrcurrentretailaverageprice ::int,
        mmrcurrentretailcleanprice ::int,
        primeunit, 
        aucguart,  
        byrno,
        vnzip1,    
        vnst,
        vehbcost,
        isonlinesale,  
        warrantycost 
    from
        trn_ex_dt.all_car_data
    where
        mmracquisitionauctionaverageprice != 'NULL' and
        mmracquisitionauctioncleanprice != 'NULL' and
        mmracquisitionretailaverageprice != 'NULL' and
        mmracquisitonretailcleanprice != 'NULL' and
        mmrcurrentauctionaverageprice != 'NULL' and
        mmrcurrentauctioncleanprice !=  'NULL' and
        mmrcurrentretailaverageprice != 'NULL' and
        mmrcurrentretailcleanprice != 'NULL' and
        transmission is NOT NULL   
) distributed by (vnst);

--step 2: aggregating features to predict IsBadBuy based on
--VehicleAge, Odometer reading, Price etc

drop aggregate if exists array_agg_array(anyarray) cascade;
create ordered aggregate array_agg_array(anyarray)
(
    sfunc = array_cat,
    stype = anyarray
);

drop table if exists trn_ex_dt.plr_train_data_dt_features;
create table trn_ex_dt.plr_train_data_dt_features as
(
    select
        vnst,
        array_agg_array(features order by refid) as features_matrix,
        max(array_upper(features, 1)) as num_features
    from
    (
        select
            vnst,
            refid,
            array[
                isbadbuy,
                vehyear,
                vehicleage,
                vehodo,
                mmracquisitionauctionaverageprice,
                mmracquisitionauctioncleanprice,
                mmracquisitionretailaverageprice,
                mmracquisitonretailcleanprice,
                mmrcurrentauctionaverageprice,
                mmrcurrentauctioncleanprice,
                mmrcurrentretailaverageprice,
                mmrcurrentretailcleanprice,
                vehbcost::int,
                isonlinesale,
                warrantycost
            ] as features
        from 
             trn_ex_dt.all_car_data_fil
    )t1
    group by vnst   
) distributed by (vnst);

--step 3: PL/R Modeling code

--Question 2: is the training set balanced? 
--Solution 2:

select 
    isbadbuy,
    count(*) 
from 
    trn_ex_dt.all_car_data_fil 
group by 1;

-- Question 3: create a vector wtvec such that the positive and negative examples have
-- equal weights

create or replace function trn_ex_dt.plr_dec_tree_featmat(
    features_matrix_linear integer[], 
    num_features integer
) 
returns bytea 
as 
$$
    library(rpart)
    #convert to data frame 
    trn_data = data.frame(matrix(features_matrix_linear,ncol=num_features,byrow=TRUE));
    #create a weight vector that balances the training set
    num_pos = sum(trn_data$X1==1)
    num_neg = sum(trn_data$X1==0)
    wtvec = matrix(0,nrow=length(trn_data$X1),ncol=1);
    wtvec[trn_data$X1==0]=0.5/num_neg;
    wtvec[trn_data$X1==1]=0.5/num_pos;
    trn_data$X1 = factor(trn_data$X1, levels = c(0,1))                                    
    f1 = formula(X1 ~ .);
    #fit a decision tree with weight vector and information gain as splitting criterion
    fit = rpart(f1,data = trn_data,weights = wtvec,parms = list(split="information"));
    return(serialize(fit, NULL))
$$ language 'plr';

--step 4: Build N decision trees in parallel for each state
--select only states that have atleast 1000 data points for building the model

drop table if exists trn_ex_dt.plr_dectree_models cascade; 
create table trn_ex_dt.plr_dectree_models as 
(
    select
        vnst, 
        (trn_ex_dt.plr_dec_tree_featmat(features_matrix,num_features)) as dec_tree_mdl 
    from 
        trn_ex_dt.plr_train_data_dt_features
    where 
        vnst in 
        (
            select 
                vnst 
            from 
            (
                select 
                    vnst,
                    count(*) 
                from 
                    trn_ex_dt.all_car_data_fil 
                group by 1 
                order by 2 desc
            )foo 
            where count > 1000
        )   
) distributed by (vnst);

--step 5: check performance on training data
drop type if exists trn_ex_dt.dt_return_type cascade;
create type trn_ex_dt.dt_return_type 
as 
(
    actual_label int, 
    pred_label int
); 

create or replace function trn_ex_dt.plr_dec_tree_score(
    fit bytea,
    features_matrix_linear integer[], 
    num_features integer
)
returns setof trn_ex_dt.dt_return_type 
as 
$$ 
    library(rpart)
    test_data = data.frame(matrix(features_matrix_linear,ncol=num_features,byrow=TRUE));
    dtres <- unserialize(fit)
    predictions <- predict(dtres,test_data,type = 'class')    
    return(data.frame(test_data$X1,predictions))
$$ language 'plr'; 


--score on training set
drop table if exists trn_ex_dt.plr_dectree_predictions_train cascade;
create table trn_ex_dt.plr_dectree_predictions_train as 
(
    select
         vnst,
         (predicted).actual_label,
         (predicted).pred_label
    from
    (
        select 
            dt.vnst,
            trn_ex_dt.plr_dec_tree_score(   
                dt.dec_tree_mdl,
                features_matrix,
                num_features
            ) as predicted
        from
            trn_ex_dt.plr_train_data_dt_features train,
            trn_ex_dt.plr_dectree_models dt
        where dt.vnst = train.vnst
    )foo
)distributed randomly;

--confusion matrix on performance for each state
--Question 4: Write sql to compute the confusion matrix to measure classification performance?
--solution 4: computes the confusion matrix for each model
select
    vnst,
    actual_label,
    pred_label,
    count(*)
from
    trn_ex_dt.plr_dectree_predictions_train
group by 1,2,3 
order by 1,2,3;

/* Result
vnst | actual_label | pred_label | count 
------+--------------+------------+-------
 AZ   |            0 |          0 |  4260
 AZ   |            0 |          1 |  1193
 AZ   |            1 |          0 |   396
 AZ   |            1 |          1 |   308
 CA   |            0 |          0 |  3934
 CA   |            0 |          1 |  2184
 CA   |            1 |          0 |   431
 CA   |            1 |          1 |   517
 CO   |            0 |          0 |  2639
 CO   |            0 |          1 |  1728
 CO   |            1 |          0 |   233
 CO   |            1 |          1 |   366
*/
