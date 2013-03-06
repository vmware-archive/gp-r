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

SELECT plr_lm( sex, length, diameter, height, whole_weight, shucked_weight, 
				viscera_weight, shell_weight, rings )
FROM abalone_array;

