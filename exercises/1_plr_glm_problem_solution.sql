----------------------------------------------------------------------------------------------------------------------------------
--                         PL/R exercise for "Data Science in Practice" course.                                            --
--                           Using glm in PL/R for Regression                                                              --
--                          Srivatsan Ramanujam <sramanujam@pivotal.io>, 13-July-2015                                      --
----------------------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------------------------------
-- Problem:  Build a ridge regression model using glm to predict the effect of engine parameters on the mpg of the vehicle.           --
--           Since aerodynamics may play a significant role in a vehicle's mpg, you may want to build a separate regression     --
--           model for each body type of the vehicles (ex: hatchbacks, sedans, SUVs etc.)                                       --
----------------------------------------------------------------------------------------------------------------------------------


----------------------------------------------------------------------------------------------------------------------------------
-- Data                                                                                                                         --
----------------------------------------------------------------------------------------------------------------------------------

--  Define UCI Auto-MPG table & load the data (https://archive.ics.uci.edu/ml/machine-learning-databases/autos/)
--  Note to Students: DO NOT run the create table statement yourself. This is a one-time data loading operation
create schema trn_ex_lmridge;

drop table if exists trn_ex_lmridge.autompg;
create table trn_ex_lmridge.autompg (
    car_id serial,
    symboling int,
    normalized_losses int,
    make text,
    fuel_type text,
    aspiration text,
    num_of_doors text,
    body_style text,
    drive_wheels text,
    engine_location text,
    wheel_base float8,
    length float8,
    width float8,
    height float8,
    curb_weight float8,
    engine_type text,
    num_of_cylinders text,
    engine_size int,
    fuel_system text,
    bore float8,
    stroke float8,
    compression_ratio float8,
    horsepower int,
    peak_rpm int,
    city_mpg int,
    highway_mpg int,
    price int
) distributed by (body_style);

copy trn_ex_lmridge.autompg (
    symboling,
    normalized_losses,
    make,
    fuel_type,
    aspiration,
    num_of_doors,
    body_style,
    drive_wheels,
    engine_location,
    wheel_base,
    length,
    width,
    height,
    curb_weight,
    engine_type,
    num_of_cylinders,
    engine_size,
    fuel_system,
    bore,
    stroke,
    compression_ratio,
    horsepower,
    peak_rpm,
    city_mpg,
    highway_mpg,
    price
) 
from 
    '/data/labs/PLX/data/autompg.csv' 
with 
    delimiter ',' 
    null '?';

---------------------------------------------------------------------------------------------------------------------------
-- Solution
---------------------------------------------------------------------------------------------------------------------------

-- Here's how this would be solved in R. We'll create a UDF in PL/R to mimic this:
/*
autompg_ridgereg <- function() {
    library(MASS)
    data = read.table("autompg.csv", header=FALSE, na.strings=c("?"), sep=",")
    colnames(data) =  c('symboling','normalized_losses','make','fuel_type','aspiration','num_of_doors','body_style','drive_wheels','engine_location','wheel_base','length','width','height','curb_weight','engine_type','num_of_cylinders','engine_size','fuel_system','bore','stroke','compression_ratio','horsepower','peak_rpm','city_mpg','highway_mpg','price')
    #Add the labels
    trn_data = data[c('bore', 'stroke', 'compression_ratio', 'horsepower', 'peak_rpm')]
    #Add label
    trn_data$labels = data$city_mpg  
    #Remove null rows
    trn_data = trn_data[complete.cases(trn_data),]                           
    f1 = formula(labels ~ .);
    #fit a ridge regression model in R. Vary lambda from 0 to 0.5, in increments of 0.01
    mdl = lm.ridge(f1, data = trn_data, lambda = seq(0, 0.5, 0.01));
    #Find the coefs corresponding to best value of lambda
    coef_best = mdl$coef[,which.min(mdl$GCV)]
    #Compute predictions on training set and calculate R^2
    pred_train = scale(trn_data[c('bore', 'stroke', 'compression_ratio', 'horsepower', 'peak_rpm')], center = FALSE, scale = mdl$scales)%*% coef_best + mdl$ym
    #Return coefficient of determination
    r_square = cor(trn_data$labels, pred_train)^2
    print(c(names(coef_best), coef_best, r_square)) 
}
*/

--1) Create a function to return hostname of the system where the model is executing (to verify parallelization)
create or replace function trn_ex_lmridge.hostname()
returns text
as
$$
    import os
    return os.popen('hostname').read()
$$language plpythonu;

--2) Create a User Defined Aggregate (UDA) to combine a collection of arrays
drop aggregate if exists trn_ex_lmridge.array_agg_array(anyarray) cascade;
create ordered aggregate trn_ex_lmridge.array_agg_array(anyarray)
(
    sfunc = array_cat,
    stype = anyarray
);

--3) Create a User Defined Function to invoke the Ridge Regression Model for training
--i) Model Training
drop function if exists trn_ex_lmridge.plr_ridge_reg_train(float[], int, float[]) cascade;
create or replace function trn_ex_lmridge.plr_ridge_reg_train(
        features_matrix_linear float[], 
        num_features int, 
        labels float[]
    )
    returns bytea
as
$$
    library(MASS)
    #convert to data frame 
    trn_data = data.frame(matrix(features_matrix_linear, ncol=num_features, byrow=TRUE)); 
    #Add label column (y)
    trn_data$y = as.vector(labels) 
    #Formula for the model                        
    f1 = formula(y ~ .);
    #fit a ridge regression model in R. Vary lambda from 0 to 0.5, in increments of 0.01
    mdl = lm.ridge(f1, data = trn_data, lambda = seq(0, 0.5, 0.01));
    return (serialize(mdl, NULL))
$$ language plr;

--ii) Return Model Coefficients
drop function if exists trn_ex_lmridge.plr_ridge_reg_coefficents(bytea) cascade;
create or replace function trn_ex_lmridge.plr_ridge_reg_coefficents(
        mdl bytea
    )
    returns float8[]
as
$$
    library(MASS)
    #Deserialize the Ridge Regression Model
    mdl_obj = unserialize(mdl)
    #Return the coefs corresponding to best value of lambda
    coef_best = mdl_obj$coef[,which.min(mdl_obj$GCV)]
    return (coef_best)
$$ language plr;

--iii) Model Scoring
drop function if exists trn_ex_lmridge.plr_ridge_reg_score(float[], int, float[], bytea) cascade;
create or replace function trn_ex_lmridge.plr_ridge_reg_score(
        features_matrix_linear float[], 
        num_features int, 
        labels float[],
        mdl bytea
    )
    returns float8
as
$$
    library(MASS)
    #convert to data frame 
    trn_data = data.frame(matrix(features_matrix_linear, ncol=num_features, byrow=TRUE)); 
    #Add label column (y)
    trn_data$y = as.vector(labels) 
    #Deserialize the model object
    mdl_obj = unserialize(mdl)
    #Find the coefs corresponding to best value of lambda
    coef_best = mdl_obj$coef[,which.min(mdl_obj$GCV)]
    #Compute predictions on training set and calculate R^2
    pred_train = scale(trn_data[!colnames(trn_data) %in% c("y")], center = FALSE, scale = mdl_obj$scales)%*% coef_best + mdl_obj$ym
    #Return coefficient of determination
    r_square = cor(trn_data$y, pred_train)^2
    return (r_square)
$$ language plr;

--5) Invoke the Ridge Regression UDF on the training set to build a model for each body_type
drop table if exists trn_ex_lmridge.mdls cascade;
create table trn_ex_lmridge.mdls
as
(
    select 
        body_style, 
        trn_ex_lmridge.hostname(),
        trn_ex_lmridge.plr_ridge_reg_train(
            features_linear_mat, 
            num_features, 
            highway_mpg_arr
        ) as mdl
    from
    (
        select 
            body_style,
            trn_ex_lmridge.array_agg_array(features order by car_id) as features_linear_mat,
            max(array_upper(features, 1)) as num_features,
            array_agg(highway_mpg order by car_id) as highway_mpg_arr
        from
        (
            select 
                car_id,
                body_style,
                array[bore, stroke, compression_ratio, horsepower, peak_rpm] as features,
                highway_mpg
            from 
                trn_ex_lmridge.autompg
            where 
                bore is not null and
                stroke is not null and
                compression_ratio is not null and 
                horsepower is not null and
                peak_rpm is not null
        )q1
        group by body_style
    )q2
) distributed by (body_style);

-- Verify models were trained on different hosts and display model coefficients
select 
    body_style,
    hostname,
    trn_ex_lmridge.plr_ridge_reg_coefficents(
        mdl
    ) as coefs_best      
from
    trn_ex_lmridge.mdls
order by body_style;
/*
Results:
========
 body_style  | hostname |                                          coefs_best                                           
-------------+----------+-----------------------------------------------------------------------------------------------
 convertible | sdw5     | {-0.00410968866983508,0.804646087809787,2.97224567585072,-3.72422482321785,1.4208555934721}
             :            
 hardtop     | sdw4     | {1.61190382768922,1.54702038178955,0.257157717139535,-7.78677114696428,6.25781005179285}
             :            
 hatchback   | sdw7     | {-1.06395029573399,-0.196039218675548,2.03065517722965,-4.03165130838672,0.248264332822786}
             :            
 sedan       | sdw7     | {-1.46860441526949,-0.339699802984648,1.30184059386539,-4.73482739867677,-0.0197714049381745}
             :            
 wagon       | sdw1     | {-0.325851677442064,0.680551260809304,-0.329099777353526,-3.67790911284059,1.03743315843023}
             :            
(5 rows)
*/


--6) Model Scoring - Use the previously built models to obtain the R_square score on the training set
select 
    model.body_style, 
    trn_ex_lmridge.hostname(),
    trn_ex_lmridge.plr_ridge_reg_score(
        features_linear_mat, 
        num_features, 
        highway_mpg_arr,
        model.mdl
    ) as r_square_train,
    trn_ex_lmridge.plr_ridge_reg_coefficents(
        mdl
    ) as coefs_best  
from
(
    select 
        body_style,
        trn_ex_lmridge.array_agg_array(features order by car_id) as features_linear_mat,
        max(array_upper(features, 1)) as num_features,
        array_agg(highway_mpg order by car_id) as highway_mpg_arr
    from
    (
        select 
            car_id,
            body_style,
            array[bore, stroke, compression_ratio, horsepower, peak_rpm] as features,
            highway_mpg
        from 
            trn_ex_lmridge.autompg
        where 
            bore is not null and
            stroke is not null and
            compression_ratio is not null and 
            horsepower is not null and
            peak_rpm is not null
    )q1
    group by body_style
)q2, trn_ex_lmridge.mdls model
where 
    q2.body_style = model.body_style
order by body_style;
/*
Results:
=========

 body_style  | hostname |  r_square_train   |                                          coefs_best                                           
-------------+----------+-------------------+-----------------------------------------------------------------------------------------------
 convertible | sdw5     |                 1 | {-0.00410968866983508,0.804646087809787,2.97224567585072,-3.72422482321785,1.4208555934721}
             :                                
 hardtop     | sdw4     |                 1 | {1.61190382768922,1.54702038178955,0.257157717139535,-7.78677114696428,6.25781005179285}
             :                                
 hatchback   | sdw7     |  0.67323987012899 | {-1.06395029573399,-0.196039218675548,2.03065517722965,-4.03165130838672,0.248264332822786}
             :                                
 sedan       | sdw7     | 0.758031752819048 | {-1.46860441526949,-0.339699802984648,1.30184059386539,-4.73482739867677,-0.0197714049381745}
             :                                
 wagon       | sdw1     | 0.752125634264389 | {-0.325851677442064,0.680551260809304,-0.329099777353526,-3.67790911284059,1.03743315843023}
             :                                
(5 rows)
*/
----------------------------------------------------------------------------------------------------------------------------------
