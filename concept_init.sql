
CREATE SCHEMA IF NOT EXISTS concept;
SET search_path TO concept;

DROP table if exists requests;
DROP table if exists responses;
DROP table if exists bodies;

-- system

CREATE TABLE IF NOT EXISTS routes (route text, method text, request_table text, response_table text);

INSERT INTO routes VALUES('/', 'GET', 'root');

CREATE TABLE IF NOT EXISTS requests (id uuid primary key, uri text, headers jsonb, body bytea, params jsonb, query jsonb);

CREATE TABLE IF NOT EXISTS responses (id uuid primary key, status int, reason text, headers jsonb, chunked boolean);

CREATE TABLE IF NOT EXISTS bodies (id uuid, num int, last boolean, "offset" int, length int, data bytea);

-- testing

/*This function to be used from another js functions*/
CREATE OR REPLACE FUNCTION user_chunked_body(req bytea, resp bytea) RETURNS INT AS
$$
    const max_data_size = 64 * 1024 - 1;
    var name = req.uri;

    var start_pos = resp.body.offset + 1

    var datas = plv8.execute(
        'SELECT substring(image from $2 for $3) as data, octet_length(image) as size FROM user_files WHERE name = $1',
        [name, start_pos, max_data_size]);
    if (datas.length) {
      data = datas[0]
      if (data.size > start_pos + data.data.length) {
        resp.body.last = false;
        resp.chunked = true;
      }
      else {
        resp.body.last = true;
      }
      resp.body.data = data.data;
    }
    else {	
      plv8.elog(WARNING, 'No data for file', name);	
      resp.body.last = true;	
    }
$$
LANGUAGE plv8;

DROP FUNCTION IF EXISTS req_handler() CASCADE;
CREATE FUNCTION req_handler() RETURNS TRIGGER AS
$$
  function user_resp_function(req, resp) {
    var user_chunked_body = plv8.find_function('user_chunked_body');
    user_chunked_body(req, resp);
  }
  
  var req = {
    id: NEW.id,
    uri: NEW.uri,
    headers: NEW.headers,
    body: NEW.body,
    params: NEW.params,
    query: NEW.query
  };
  var resp = {
     id: NEW.id,
     status: 200,
     reason: 'OK',
     headers: {},
     chunked: false,
     body: {
       offset: 0,
       last: false,
       data: ''
     }
  };
  user_resp_function(req, resp);

  plv8.execute('INSERT INTO responses VALUES($1, $2, $3, $4, $5)',
               [NEW.id, resp.status, resp.reason, resp.headers, resp.chunked]);
  if (resp.chunked) {
    resp.headers["Transfer-Encoding"] = "chunked";
  } else {
    resp.headers["Content-Length"] = resp.body.data.length;
  }

  plv8.execute('INSERT INTO bodies(id, num, last, "offset", length, data) \
                VALUES($1, $2, $3, $4, $5, $6)',
                [NEW.id, 1, resp.body.last,
                resp.body.offset, resp.body.data.length, resp.body.data]);
  return NEW;
$$
LANGUAGE "plv8";

DROP FUNCTION IF EXISTS resp_body_handler() CASCADE;
CREATE FUNCTION resp_body_handler() RETURNS TRIGGER AS
$$  
  var req = plv8.execute('SELECT * FROM requests WHERE id = $1', [NEW.id])[0];
  var resp = plv8.execute('SELECT * FROM responses WHERE id = $1', [NEW.id])[0];

  resp.body = {
    offset: NEW.offset + NEW.length,
    last: false,
    data: ''
  };

  var user_chunked_body = plv8.find_function('user_chunked_body');
  user_chunked_body(req, resp);
  var num = NEW.num + 1;
  
  plv8.execute('INSERT INTO bodies(id, num, last, "offset", length, data) \
                VALUES($1, $2, $3, $4, $5, $6)',
                [NEW.id, num, resp.body.last,
                resp.body.offset, resp.body.data.length, resp.body.data]);

  return NEW;
$$
LANGUAGE "plv8";

DROP TRIGGER IF EXISTS req_handler ON requests;
CREATE TRIGGER req_handler AFTER INSERT ON requests
    FOR EACH ROW EXECUTE PROCEDURE req_handler();

DROP TRIGGER IF EXISTS resp_body_handler ON bodies;
CREATE TRIGGER resp_body_handler AFTER INSERT ON bodies
    FOR EACH ROW 
    WHEN (NEW.last is false)
    EXECUTE PROCEDURE resp_body_handler();

