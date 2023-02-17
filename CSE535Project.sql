CREATE DATABASE CSE535Project;
CREATE USER 'cse535'@'localhost' IDENTIFIED BY 'taforever';
GRANT ALL PRIVILEGES ON * . * TO 'cse535'@'localhost';
FLUSH PRIVILEGES;
USE CSE535Project; #Default DB 

SET FOREIGN_KEY_CHECKS=0; #Disable ALL foreign key constraint checks

CREATE TABLE CUSTOMER
	(`id`			INT	NOT NULL,
	 `name`			VARCHAR(64) NOT NULL,
	 `address`		VARCHAR(64)	NOT NULL,
	 `credit-card`	CHAR(16) NOT NULL,
    PRIMARY KEY(`id`)
    );
    
    CREATE TABLE AUTOPOD
	(`vin`			CHAR(16)	NOT NULL,
	 `model`		VARCHAR(64) NOT NULL,
	 `color`		VARCHAR(16)	NOT NULL,
	 `year`			INT NOT NULL,
    PRIMARY KEY(`vin`)
    );
    
    CREATE TABLE STATION
	(`id`			INT	NOT NULL,
	 `location`		VARCHAR(64) NOT NULL,
	 `num-holds`	INT	NOT NULL,
    PRIMARY KEY(`id`)
    );
    
    CREATE TABLE AVAILABLE
	(`vin`			CHAR(16),
     `station-id`	INT,
     PRIMARY KEY(`vin`),
     CONSTRAINT Svin FOREIGN KEY(`vin`) REFERENCES AUTOPOD(`vin`),
     CONSTRAINT Sid FOREIGN KEY(`station-id`) REFERENCES STATION(`id`)
    );
    
	CREATE TABLE RENTAL
	(`vin`			CHAR(16)	NOT NULL,
     `cust-id`		INT	NOT NULL,
     `src`			INT NOT NULL,
     `date`			DATE NOT NULL,
     `time`			TIME NOT NULL,
     PRIMARY KEY(`vin`, `cust-id`, `date`, `time`),
     CONSTRAINT Avin FOREIGN KEY(`vin`) REFERENCES AUTOPOD(`vin`),
     CONSTRAINT Cid FOREIGN KEY(`cust-id`) REFERENCES CUSTOMER(`id`),
     CONSTRAINT STid FOREIGN KEY(`src`) REFERENCES STATION(`id`)
    );
    
    CREATE TABLE COMPLETEDTRIP
    (`vin`					CHAR(16)	NOT NULL,
     `cid`					INT	NOT NULL,
     `init-date`			DATE NOT NULL,
     `init-time`			TIME NOT NULL,
     `end-date`				DATE NOT NULL,
     `end-time`				TIME NOT NULL,
     `origin-station`		INT NOT NULL,
     `destination-station`	INT NOT NULL,
     `cost`					DECIMAL(6,2) NOT NULL,
     PRIMARY KEY(`vin`,`cid`,`init-date`,`init-time`),
     CONSTRAINT Avvin FOREIGN KEY(`vin`) REFERENCES AUTOPOD(`vin`),
     CONSTRAINT Ccid FOREIGN KEY(`cid`) REFERENCES CUSTOMER(`id`),
     CONSTRAINT Oid FOREIGN KEY(`origin-station`) REFERENCES STATION(`id`),
     CONSTRAINT Did FOREIGN KEY(`destination-station`) REFERENCES STATION(`id`)
    );
    #INSERT INTO AVAILABLE () VALUES (NEW.`vin`, (SELECT DISTINCT `station-id` FROM STATION, AVAILABLE WHERE `id` = `station-id` GROUP BY `id` HAVING MIN(COUNT(`station-id`)) < `num-holds`));
	DELIMITER &&
    CREATE TRIGGER assign_station
    BEFORE INSERT ON AUTOPOD
    FOR EACH ROW
    BEGIN
		IF EXISTS (SELECT DISTINCT `id`, COUNT(`station-id`), `num-holds` FROM STATION, AVAILABLE WHERE `id` = `station-id` GROUP BY `id` HAVING COUNT(`station-id`) < `num-holds`)
			THEN CREATE TEMPORARY TABLE POSS AS (SELECT DISTINCT `id` as `A`, COUNT(`station-id`) AS `B`, `num-holds` AS `C` FROM STATION, AVAILABLE WHERE `id` = `station-id` GROUP BY `id` HAVING COUNT(`station-id`) < `num-holds`);
			INSERT INTO AVAILABLE () VALUES (NEW.`vin`, (SELECT `A` FROM POSS ORDER BY `B` ASC LIMIT 1));
            DROP TEMPORARY TABLE POSS;
		
		ELSEIF NOT EXISTS (SELECT * FROM AVAILABLE)
			THEN INSERT INTO AVAILABLE () VALUES (NEW.`vin`, (SELECT `id` FROM STATION ORDER BY `id` ASC LIMIT 1));
		
		ELSEIF NOT EXISTS (SELECT DISTINCT `id` FROM STATION, AVAILABLE WHERE `id` = `station-id`)
			THEN CREATE TEMPORARY TABLE POSS AS (SELECT `id` AS `A` FROM STATION, AVAILABLE WHERE `id` != `station-id`);
			INSERT INTO AVAILABLE () VALUES (NEW.`vin`, (SELECT `A` FROM POSS ORDER BY `A` ASC LIMIT 1));
            DROP TEMPORARY TABLE POSS;
		ELSE
			SIGNAL SQLSTATE '45001' SET MESSAGE_TEXT = "ERROR: all stations full";
		
		END IF;
	END&&
    DELIMITER ;
        
	DELIMITER &&
    CREATE TRIGGER vehicle_retire
    BEFORE DELETE ON AUTOPOD
    FOR EACH ROW
    BEGIN
		IF NOT EXISTS (SELECT DISTINCT `A`.`vin` FROM AUTOPOD AS `A`, RENTAL AS `R` WHERE `A`.`vin` = `R`.`vin`)
			THEN DELETE FROM AVAILABLE WHERE OLD.`vin` = `vin`;
		END IF;
	END&&
    DELIMITER ;
	
	DELIMITER &&
	CREATE PROCEDURE StartTrip (IN `vin` CHAR(16), IN `cid` INT)
	BEGIN
		IF EXISTS (SELECT `V`.`vin` FROM AVAILABLE AS `V` WHERE StartTrip.`vin` = `V`.`vin`) AND EXISTS (SELECT `I`.`id` FROM CUSTOMER AS `I` WHERE StartTrip.`cid` = `I`.`id`)
			THEN SET @sid = (SELECT `station-id` FROM AVAILABLE as `L` WHERE StartTrip.`vin` = `L`.`vin`);
            DELETE FROM AVAILABLE WHERE AVAILABLE.`vin` = StartTrip.`vin`;
			INSERT INTO RENTAL () VALUES (StartTrip.`vin`, StartTrip.`cid`, @sid, DATE(NOW()), TIME(NOW()));
		ELSE 
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = "ERROR: parameters are not correct and/or vehicle is not in AVAILABLE";
		END IF;
	END&&
	DELIMITER ;
    
    DELIMITER &&
	CREATE PROCEDURE EndTrip (IN `vin` CHAR(16), IN `cid` INT, IN `dest` INT, IN `cost` DECIMAL(6,2))
	BEGIN
		IF NOT EXISTS (SELECT DISTINCT `id` FROM STATION, AVAILABLE WHERE `id` = `station-id` AND `id` = EndTrip.`dest` GROUP BY `id` HAVING COUNT(`station-id`) < `num-holds`)
			THEN SIGNAL SQLSTATE '45002' SET MESSAGE_TEXT = "ERROR: destination station already full";
		ELSEIF EXISTS (SELECT `D`.`vin` FROM RENTAL AS `D` WHERE EndTrip.`vin` = `D`.`vin` AND EndTrip.`cid` = `D`.`cust-id`)
			THEN INSERT INTO COMPLETEDTRIP () VALUES (EndTrip.`vin`, (SELECT `init-date` FROM RENTAL as `R` WHERE EndTrip.`vin` = `R`.`vin`), (SELECT `init-time` FROM RENTAL as `R` WHERE EndTrip.`vin` = `R`.`vin`), EndTrip.`cid`, DATE(NOW()), TIME(NOW()), (SELECT `src` FROM RENTAL as `R` WHERE EndTrip.`vin` = `R`.`vin`), EndTrip.`dest`, EndTrip.`cost`);
            DELETE FROM RENTAL WHERE EndTrip.`vin` = RENTAL.`vin` AND EndTrip.`cid` = RENTAL.`cust-id`;
            INSERT INTO AVAILABLE () VALUES (EndTrip.`vin`, EndTrip.`dest`);
		ELSE
        SIGNAL SQLSTATE '45003' SET MESSAGE_TEXT = "ERROR: vehicle and/or customer does not exist in RENTAL";
        END IF;
	END&&
	DELIMITER ;