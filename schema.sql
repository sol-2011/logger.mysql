DROP PROCEDURE IF EXISTS insert_logline;
DELIMITER //
CREATE procedure insert_logline(host varchar(16), name varchar(256), stag varchar(50), facility tinyint unsigned, severity tinyint unsigned, msg text, tim varchar(50))
LANGUAGE SQL
NOT DETERMINISTIC
SQL SECURITY INVOKER
COMMENT 'Insert logline with check device table'
BEGIN
  DECLARE devid integer unsigned default null;

  SELECT id INTO devid FROM devices WHERE ip = inet_aton(host);

  IF (devid IS NULL) THEN
    INSERT devices (ip, model, name) VALUES (inet_aton(host), concat('model ', host), concat('device ', host));
    SELECT id INTO devid FROM devices WHERE ip = inet_aton(host);
  END IF;

  INSERT INTO logs (device, logstring, facility, severity, hname, tag, htime) VALUES (devid, msg, facility, severity, name, stag, tim);

END;
//
DELIMITER ;

DROP TABLE IF EXISTS logs;
CREATE TABLE logs (
    id integer unsigned not null AUTO_INCREMENT,
    `date` datetime DEFAULT current_timestamp() NOT NULL,
    device integer unsigned NOT NULL,
    logstring text NOT NULL,
    facility tinyint unsigned,
    severity tinyint unsigned,
    tag varchar(50),
    hname varchar(128),
    htime varchar(50),
    PRIMARY KEY (`id`)
);

DROP TABLE IF EXISTS devices;
CREATE TABLE devices (
    id integer unsigned NOT NULL AUTO_INCREMENT,
    ip integer unsigned NOT NULL,
    model varchar(250) NOT NULL,
    name varchar(250) NOT NULL,
    comment text,
    PRIMARY KEY (`id`)
);


alter table logs add foreign key (device) references devices (id);

CREATE INDEX device_id_idx ON devices (id);

CREATE INDEX device_ip_idx ON devices (ip);

CREATE INDEX device_model_idx ON devices (model);

CREATE INDEX device_name_idx ON devices (name);

CREATE INDEX logs_date_idx ON logs (`date`);

CREATE INDEX logs_facility_idx ON logs (facility);

CREATE INDEX logs_severity_idx ON logs (severity);

