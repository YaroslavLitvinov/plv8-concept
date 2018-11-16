cat cmpl.zip | base64 -w 0 | psql -c "
CREATE SCHEMA IF NOT EXISTS concept;
SET search_path TO concept;

CREATE TEMP TABLE base64_binary(data text); 
COPY base64_binary FROM STDIN; 

DROP table if exists user_files;
create table user_files(name text PRIMARY KEY, image bytea);
insert into user_files values ('/files/hello', 'hello');
INSERT INTO user_files 
SELECT '/files/cmpl.zip' as name, decode(data, 'base64') as image FROM base64_binary;
SELECT name, octet_length(image) as size FROM user_files;
"

psql -f concept_init.sql
psql -f concept_user.sql
