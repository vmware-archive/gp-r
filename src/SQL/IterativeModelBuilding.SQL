DROP FUNCTION IF EXISTS plr_lm( sex text[], length float8[], diameter float8[],
        height float8[], whole_weight float8[], 
        shucked_weight float8[], viscera_weight float8[], 
        shell_weight float8[], rings float8[] );
CREATE OR REPLACE FUNCTION plr_lm( sex text[], length float8[], diameter float8[],
        height float8[], whole_weight float8[], 
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


-- How long does it take to build a single model
-- 170 ms
SELECT plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, 
    viscera_weight, shell_weight, rings )
FROM abalone_array;

DROP FUNCTION IF EXISTS IterativePLRModels( INTEGER );
CREATE OR REPLACE FUNCTION IterativePLRModels( INTEGER ) 
RETURNS SETOF TEXT 
AS $BODY$
DECLARE
  n ALIAS FOR $1;
BEGIN
  FOR i IN 1..n LOOP
    RAISE NOTICE 'Processing %', i;
    PERFORM plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, 
        viscera_weight, shell_weight, rings )
    FROM abalone_array;
    RETURN NEXT i::TEXT;
  END LOOP;
END
$BODY$
  LANGUAGE plpgsql;

-- How long does it take to build 64 models sequentially
-- 2904 ms
SELECT IterativePLRModels( 64 );

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

-- Create 64 copies
SELECT ReplicateAbaloneArrays( 64 );

-- How long does it take to run 64 in parallel?
-- 271 ms
SELECT plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, 
    viscera_weight, shell_weight, rings )
FROM abalone_array_replicates;
-----------------
(64 rows)

Time: 183.937 ms


