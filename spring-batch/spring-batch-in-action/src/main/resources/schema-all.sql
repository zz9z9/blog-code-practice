
--Spring Boot runs schema-@@platform@@.sql automatically during startup. -all is the default for all platforms.

create table if not exists people (
    person_id bigint auto_increment primary key,
    first_name varchar(20),
    last_name varchar(20)
);