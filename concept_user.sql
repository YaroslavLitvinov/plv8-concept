SET search_path TO concept;

INSERT INTO requests(id, uri, headers, body, params, query)
VALUES('A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11',
       '/files/hello', '{}', null, '{}', '{}');

--INSERT INTO requests(id, uri, headers, body, params, query)
--VALUES('A0EEBC00-9C0B-4EF8-BB6D-6BB9BD380A11',
--       '/files/cmpl.zip', '{}', null, '{}', '{}');

select * from responses;
select id, num, last, "offset", length from bodies;
