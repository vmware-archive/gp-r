----------------------------------------------------------------------------------------------------------------------------------
--                PL/R exercise for "Data Science in Practice" course                                                           --
--                                 Random Forests in PL/R                                                                       --
--                  July-5, 2015: Regunathan Radhakrishnan <rradhakrishnan@pivotal.io> -  Exercise design                       --
--                  July-8, 2015: Srivatsan Ramanujam <sramanujam@pivotal.io> - SQL Optimizations                               --
----------------------------------------------------------------------------------------------------------------------------------

--Using cartographic variables to classify forest types
--The study area includes four wilderness areas located in the Roosevelt National 
--Forest of northern Colorado. Each observation is a 30m x 30m patch. You are asked
--to predict an integer classification for the forest cover type. The seven types are:
--https://www.kaggle.com/c/forest-cover-type-prediction

--1 - Spruce/Fir
--2 - Lodgepole Pine
--3 - Ponderosa Pine
--4 - Cottonwood/Willow
--5 - Aspen
--6 - Douglas-fir
--7 - Krummholz
--
--The training set (15120 observations) contains both features and the Cover_Type. The test set contains only the features.
--You must predict the Cover_Type for every row in the test set (565892 observations).
--
-- Data Fields
-- -----------
--
--Elevation - Elevation in meters
--Aspect - Aspect in degrees azimuth
--Slope - Slope in degrees
--Horizontal_Distance_To_Hydrology - Horz Dist to nearest surface water features
--Vertical_Distance_To_Hydrology - Vert Dist to nearest surface water features
--Horizontal_Distance_To_Roadways - Horz Dist to nearest roadway
--Hillshade_9am (0 to 255 index) - Hillshade index at 9am, summer solstice
--Hillshade_Noon (0 to 255 index) - Hillshade index at noon, summer solstice
--Hillshade_3pm (0 to 255 index) - Hillshade index at 3pm, summer solstice
--Horizontal_Distance_To_Fire_Points - Horz Dist to nearest wildfire ignition points
--Wilderness_Area (4 binary columns, 0 = absence or 1 = presence) - Wilderness area designation
--Soil_Type (40 binary columns, 0 = absence or 1 = presence) - Soil Type designation
--Cover_Type (7 types, integers 1 to 7) - Forest Cover Type designation
--
--The wilderness areas are:
--
--1 - Rawah Wilderness Area
--2 - Neota Wilderness Area
--3 - Comanche Peak Wilderness Area
--4 - Cache la Poudre Wilderness Area
--
--The soil types are:
--
--1 Cathedral family - Rock outcrop complex, extremely stony.
--2 Vanet - Ratake families complex, very stony.
--3 Haploborolis - Rock outcrop complex, rubbly.
--4 Ratake family - Rock outcrop complex, rubbly.
--5 Vanet family - Rock outcrop complex complex, rubbly.
--6 Vanet - Wetmore families - Rock outcrop complex, stony.
--7 Gothic family.
--8 Supervisor - Limber families complex.
--9 Troutville family, very stony.
--10 Bullwark - Catamount families - Rock outcrop complex, rubbly.
--11 Bullwark - Catamount families - Rock land complex, rubbly.
--12 Legault family - Rock land complex, stony.
--13 Catamount family - Rock land - Bullwark family complex, rubbly.
--14 Pachic Argiborolis - Aquolis complex.
--15 unspecified in the USFS Soil and ELU Survey.
--16 Cryaquolis - Cryoborolis complex.
--17 Gateview family - Cryaquolis complex.
--18 Rogert family, very stony.
--19 Typic Cryaquolis - Borohemists complex.
--20 Typic Cryaquepts - Typic Cryaquolls complex.
--21 Typic Cryaquolls - Leighcan family, till substratum complex.
--22 Leighcan family, till substratum, extremely bouldery.
--23 Leighcan family, till substratum - Typic Cryaquolls complex.
--24 Leighcan family, extremely stony.
--25 Leighcan family, warm, extremely stony.
--26 Granile - Catamount families complex, very stony.
--27 Leighcan family, warm - Rock outcrop complex, extremely stony.
--28 Leighcan family - Rock outcrop complex, extremely stony.
--29 Como - Legault families complex, extremely stony.
--30 Como family - Rock land - Legault family complex, extremely stony.
--31 Leighcan - Catamount families complex, extremely stony.
--32 Catamount family - Rock outcrop - Leighcan family complex, extremely stony.
--33 Leighcan - Catamount families - Rock outcrop complex, extremely stony.
--34 Cryorthents - Rock land complex, extremely stony.
--35 Cryumbrepts - Rock outcrop - Cryaquepts complex.
--36 Bross family - Rock land - Cryumbrepts complex, extremely stony.
--37 Rock outcrop - Cryumbrepts - Cryorthents complex, extremely stony.
--38 Leighcan - Moran families - Cryaquolls complex, extremely stony.
--39 Moran family - Cryorthents - Leighcan family complex, extremely stony.
--40 Moran family - Cryorthents - Rock land complex, extremely stony.
----------------------------------------------------------------------------------------------------------------------------------

--step 0: data loading

create schema trn_ex_rf;
drop table if exists trn_ex_rf.all_forest_data;
create table trn_ex_rf.all_forest_data
(
    id int,
    elevation int,
    aspect int,
    slope int,
    horizontal_distance_to_hydrology int,
    vertical_distance_to_hydrology int,
    horizontal_distance_to_roadways int,
    hillshade_9am int,
    hillshade_noon int,
    hillshade_3pm int,
    horizontal_distance_to_fire_points int,
    wilderness_area1 int,
    wilderness_area2 int,
    wilderness_area3 int,
    wilderness_area4 int,
    soil_type1 int,
    soil_type2 int,
    soil_type3 int,
    soil_type4 int,
    soil_type5 int,
    soil_type6 int,
    soil_type7 int,
    soil_type8 int,
    soil_type9 int,
    soil_type10 int,
    soil_type11 int,
    soil_type12 int,
    soil_type13 int,
    soil_type14 int,
    soil_type15 int,
    soil_type16 int,
    soil_type17 int,
    soil_type18 int,
    soil_type19 int,
    soil_type20 int,
    soil_type21 int,
    soil_type22 int,
    soil_type23 int,
    soil_type24 int,
    soil_type25 int,
    soil_type26 int,
    soil_type27 int,
    soil_type28 int,
    soil_type29 int,
    soil_type30 int,
    soil_type31 int,
    soil_type32 int,
    soil_type33 int,
    soil_type34 int,
    soil_type35 int,
    soil_type36 int,
    soil_type37 int,
    soil_type38 int,
    soil_type39 int,
    soil_type40 int,
    cover_type int
) distributed by (id);
--15120

copy trn_ex_rf.all_forest_data from '/data/labs/PLX/data/forestcover.csv' delimiter ',' csv header;

-- User Defined Aggregate to combine an array of arrays into a single linear array
drop aggregate if exists array_agg_array(anyarray) cascade;
create ordered aggregate array_agg_array(anyarray)
(
    sfunc = array_cat,
    stype = anyarray
);


--step 1: create 80/20 split of training set and check whether training set is balanced
--Question 1:write SQL code to create 80/20 split through stratified sampling (i.e. every class in the sample should 
-- be equally represented in terms of number of samples)
--create a table named "trn_ex_rf.training_data_subset" for training data
--create a table named "trn_ex_rf.testing_data_subset" for testing data

--Solution 1:
--checking if the labels are balanced in the input dataset
select 
  cover_type,
  count(*) 
from 
  trn_ex_rf.all_forest_data 
group  by 1;

-- Use Window Functions in SQL for stratified sampling to create training & test set in 80:20 ratio  
drop table if exists trn_ex_rf.train_and_test_set cascade;
create table trn_ex_rf.train_and_test_set
as
(
    select
        id,
        --Window Functions to create a random column which can be used for selecting training & test sets
        (
            (row_number() over (partition by cover_type order by random()))*1.0
            /
            count(*) over (partition by cover_type)
        ) as sample_pct,
        array[
            cover_type,
            elevation,
            aspect,
            slope,
            horizontal_distance_to_hydrology,
            vertical_distance_to_hydrology,
            horizontal_distance_to_roadways,
            hillshade_9am,
            hillshade_noon,
            hillshade_3pm,
            horizontal_distance_to_fire_points,
            wilderness_area1,
            wilderness_area2,
            wilderness_area3,
            wilderness_area4,
            soil_type1,
            soil_type2,
            soil_type3,
            soil_type4,
            soil_type5,
            soil_type6,
            soil_type7,
            soil_type8,
            soil_type9,
            soil_type10,
            soil_type11,
            soil_type12,
            soil_type13,
            soil_type14,
            soil_type15,
            soil_type16,
            soil_type17,
            soil_type18,
            soil_type19,
            soil_type20,
            soil_type21,
            soil_type22,
            soil_type23,
            soil_type24,
            soil_type25,
            soil_type26,
            soil_type27,
            soil_type28,
            soil_type29,
            soil_type30,
            soil_type31,
            soil_type32,
            soil_type33,
            soil_type34,
            soil_type35,
            soil_type36,
            soil_type37,
            soil_type38,
            soil_type39,
            soil_type40
        ] as features
    from 
        trn_ex_rf.all_forest_data
) distributed by (id);

-- Training set containing 80% of the rows.
-- This is stratified sampling and will ensure every class has equal representation
drop table if exists trn_ex_rf.plr_train_data_rf_features cascade;
create table trn_ex_rf.plr_train_data_rf_features
as
(

    select 
        array_agg_array(features order by id) as features_matrix,
        max(array_upper(features, 1)) as num_features 
    from
    (  
        select 
            *
        from
            trn_ex_rf.train_and_test_set
        where 
            sample_pct <= 0.80
    )q
) distributed randomly;

-- Test dataset with 20% of the rows
drop table if exists trn_ex_rf.plr_test_data_rf_features cascade;
create table trn_ex_rf.plr_test_data_rf_features
as
(
    select 
        array_agg_array(features order by id) as features_matrix,
        max(array_upper(features, 1)) as num_features 
    from
    (      
        select 
            *
        from
            trn_ex_rf.train_and_test_set
        where 
            sample_pct > 0.80
    )q
) distributed randomly;

--step 3:plr random forest modeling code
create or replace function trn_ex_rf.plr_rf_featmat(
    features_matrix_linear integer[], 
    num_features integer, 
    numtrees integer
) 
returns bytea 
as 
$$
    library(randomForest)
    #convert to data frame 
    trn_data = data.frame(matrix(features_matrix_linear, ncol=num_features,byrow=TRUE));        
    trn_data$X1 = factor(trn_data$X1, levels = c(1,2,3,4,5,6,7))
    samplesize = 0.63* length(trn_data$X1);                           
    f1 = formula(X1 ~ .);
    rfres<- randomForest(f1, data=trn_data, importance=TRUE, ntree=numtrees,replace=TRUE, sampsize=samplesize, mtry=7)	 
    return(serialize(rfres, NULL))
$$ language 'plr';

--step 4: build a random forest model
drop table if exists trn_ex_rf.plr_rf_models cascade; 
create table trn_ex_rf.plr_rf_models 
as 
(
    select
        (trn_ex_rf.plr_rf_featmat(features_matrix, num_features, 10)) as rf_mdl 
    from 
        trn_ex_rf.plr_train_data_rf_features    
) distributed randomly;

--Question 2: Write SQL code to create multiple random forest models with increasing complexity (numtrees=50,100,250)
--Also, note down the running time for training

--solution 2: running rf training code for varying numtrees

drop table if exists trn_ex_rf.plr_rf_models_50 cascade; 
create table trn_ex_rf.plr_rf_models_50 
as 
(
    select
        (trn_ex_rf.plr_rf_featmat(features_matrix,num_features,50)) as rf_mdl 
    from 
        trn_ex_rf.plr_train_data_rf_features    
) distributed randomly;

drop table if exists trn_ex_rf.plr_rf_models_100 cascade; 
create table trn_ex_rf.plr_rf_models_100 
as 
(
    select
        (trn_ex_rf.plr_rf_featmat(features_matrix,num_features,100)) as rf_mdl 
    from 
        trn_ex_rf.plr_train_data_rf_features    
) distributed randomly;

drop table if exists trn_ex_rf.plr_rf_models_250 cascade; 
create table trn_ex_rf.plr_rf_models_250 
as 
(
    select
        (trn_ex_rf.plr_rf_featmat(features_matrix,num_features,250)) as rf_mdl 
    from 
        trn_ex_rf.plr_train_data_rf_features    
) distributed randomly;


--step 5: check performance on training and testing data
drop type if exists trn_ex_rf.rf_return_type cascade;
create type trn_ex_rf.rf_return_type 
as 
(
    actual_label int, 
    pred_label int
); 

create or replace function trn_ex_rf.plr_rf_score(
    rf_mdl bytea,
    features_matrix_linear integer[], 
    num_features integer 
)
returns setof trn_ex_rf.rf_return_type 
as 
$$ 
    library(randomForest)
    test_data = data.frame(matrix(features_matrix_linear,ncol=num_features,byrow=TRUE));
    rfres <- unserialize(rf_mdl)
    predictions <- predict(rfres,test_data,type = 'response')	
    return(data.frame(test_data$X1,predictions))
$$ language 'plr'; 

--score on test set
drop table if exists trn_ex_rf.plr_rf_predictions_test cascade;
create table trn_ex_rf.plr_rf_predictions_test 
as 
(
    select
        (predicted).actual_label,
        (predicted).pred_label
    from
    (
        select 
        	trn_ex_rf.plr_rf_score(	
        		rf.rf_mdl,
        		features_matrix,
        		num_features
        	) as predicted
        from
        	trn_ex_rf.plr_test_data_rf_features test,
        	trn_ex_rf.plr_rf_models rf
    )foo
)distributed randomly;	

-- Display confusion matrix
select 
    actual_label,
    pred_label,
    count(*) 
from 
    trn_ex_rf.plr_rf_predictions_test 
group by 1,2 
order by 1,2;

--score on training set
drop table if exists trn_ex_rf.plr_rf_predictions_train cascade;
create table trn_ex_rf.plr_rf_predictions_train as 
(
    select
        (predicted).actual_label,
        (predicted).pred_label
    from
    (
        select 
        	trn_ex_rf.plr_rf_score(	
        		rf.rf_mdl,
        		features_matrix,
        		num_features
        	) as predicted
        	
        from
        	trn_ex_rf.plr_train_data_rf_features train,
        	trn_ex_rf.plr_rf_models rf
    ) foo
) distributed randomly;

-- Confusion matrix on training set
select 
    actual_label,
    pred_label,
    count(*) 
from 
    trn_ex_rf.plr_rf_predictions_train 
group by 1,2 
order by 1,2;

--Question 3: Compute the performance on training set and test set for the other random forest models (50,100,250)?
--Solution 3:

--score on test set using rf model with 50 trees

drop table if exists trn_ex_rf.plr_rf_predictions_test_50 cascade;
create table trn_ex_rf.plr_rf_predictions_test_50 as 
(
    select
        (predicted).actual_label,
        (predicted).pred_label
    from
    (
        select 
        	trn_ex_rf.plr_rf_score(	
        		rf.rf_mdl,
        		features_matrix,
        		num_features
        	) as predicted
        from
        	trn_ex_rf.plr_test_data_rf_features test,
        	trn_ex_rf.plr_rf_models_50 rf
    )foo
)distributed randomly;	

select 
    actual_label,
    pred_label,
    count(*) 
from 
    trn_ex_rf.plr_rf_predictions_test_50 
group by 1,2 
order by 1,2;

--score on training set using rf model with 50 trees

drop table if exists trn_ex_rf.plr_rf_predictions_train_50 cascade;
create table trn_ex_rf.plr_rf_predictions_train_50 as 
(
    select
        (predicted).actual_label,
        (predicted).pred_label
    from
    (
        select
        	trn_ex_rf.plr_rf_score(	
        		rf.rf_mdl,
        		features_matrix,
        		num_features
        	) as predicted
        from
            trn_ex_rf.plr_train_data_rf_features train,
            trn_ex_rf.plr_rf_models_50 rf
    )foo
) distributed randomly;

select 
    actual_label,
    pred_label,
    count(*) 
from 
    trn_ex_rf.plr_rf_predictions_train_50 
group by 1,2 
order by 1,2;

--similarly repeat for rf models with 100 and 250 trees.
