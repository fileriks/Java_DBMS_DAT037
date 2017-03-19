CREATE TABLE Countries(
name TEXT CHECK(name ~ '^[^0-9]*$'),
PRIMARY KEY(name)
);

CREATE TABLE Areas(
country TEXT NOT NULL,
name TEXT NOT NULL CHECK (name ~ '^[^0-9]*$'), 
population INT NOT NULL CHECK (population >= 0),
PRIMARY KEY(name,country), 
FOREIGN KEY(country) REFERENCES Countries(name)
);

CREATE TABLE Towns(
country TEXT NOT NULL,
name TEXT NOT NULL, 
PRIMARY KEY(name,country),
FOREIGN KEY(country,name) REFERENCES Areas(country,name)
);

CREATE TABLE Cities (
country TEXT NOT NULL,
name TEXT NOT NULL,
visitbonus NUMERIC NOT NULL CHECK (visitbonus >=0),
PRIMARY KEY (name,country), 
FOREIGN KEY(country,name) REFERENCES Areas(country,name)
);

CREATE TABLE Persons(
country TEXT NOT NULL,
personnummer TEXT NOT NULL, 
name TEXT NOT NULL, 
locationcountry TEXT NOT NULL, 
locationarea TEXT NOT NULL, 
budget NUMERIC NOT NULL CHECK(budget >= 0.0),
PRIMARY KEY(personnummer,country), 
FOREIGN KEY (country) REFERENCES Countries(name), 
FOREIGN KEY (locationcountry,locationarea) REFERENCES Areas(country,name), 
CONSTRAINT valid_persnr CHECK (personnummer ~'^[0-9]{8}-[0-9]{4}$' OR (personnummer= '' AND country = '')),
CONSTRAINT pos_budget CHECK (budget >= 0.0)
);

CREATE TABLE Hotels(
name TEXT NOT NULL,
locationcountry TEXT NOT NULL, 
locationname TEXT NOT NULL, 
ownercountry TEXT NOT NULL, 
ownerpersonnummer TEXT NOT NULL,
PRIMARY KEY (locationcountry,locationname,ownercountry,ownerpersonnummer), 
FOREIGN KEY (locationcountry,locationname) REFERENCES Cities(country,name),
FOREIGN KEY (ownercountry,ownerpersonnummer) REFERENCES Persons(country,personnummer)
);

CREATE TABLE Roads(
fromcountry  TEXT NOT NULL,
fromarea TEXT NOT NULL,
tocountry TEXT NOT NULL,
toarea TEXT NOT NULL,
ownercountry TEXT NOT NULL,
ownerpersonnummer TEXT NOT NULL,
roadtax NUMERIC NOT NULL CHECK (roadtax >=0) DEFAULT getval('roadtax'),
PRIMARY KEY (fromcountry,fromarea,tocountry,toarea,ownercountry,ownerpersonnummer),
FOREIGN KEY (fromcountry,fromarea) REFERENCES Areas(country,name), 
FOREIGN KEY (tocountry,toarea) REFERENCES Areas(country,name),
FOREIGN KEY (ownercountry,ownerpersonnummer) REFERENCES Persons(country,personnummer),
CONSTRAINT same_start_end CHECK ((toarea,tocountry) <> (fromarea,fromcountry))
);


CREATE VIEW NextMoves AS
SELECT country AS personcountry,personnummer,locationcountry AS country,locationarea AS area,destarea,destcountry, MIN(CASE WHEN personnummer = ownerpersonnummer AND ownercountry = country THEN 0 ELSE cost END) AS cost FROM
(SELECT Roads.ownerpersonnummer,Roads.ownercountry,Persons.country,Persons.personnummer,Persons.locationcountry,Persons.locationarea,
Roads.toarea AS destarea, Roads.tocountry AS destcountry, Roads.roadtax AS cost
FROM Persons,Roads 
WHERE (Persons.locationcountry = Roads.fromcountry 
AND Persons.locationarea = Roads.fromarea AND Persons.personnummer <> '')
UNION 
SELECT Roads.ownerpersonnummer,Roads.ownercountry, Persons.country,Persons.personnummer,Persons.locationcountry,Persons.locationarea,
Roads.fromarea AS destarea, Roads.fromcountry AS destcountry, Roads.roadtax AS cost
FROM Persons,Roads 
WHERE (Persons.locationcountry = Roads.tocountry 
AND Persons.locationarea = Roads.toarea AND Persons.personnummer <> '')
) AS tmp
GROUP BY tmp.country,personnummer,locationcountry,locationarea,
destarea,destcountry ; 


CREATE VIEW NextMoves2 AS
SELECT country AS personcountry,personnummer,fromar,fromcr,destarea,destcountry, MIN(CASE WHEN personnummer = ownerpersonnummer AND ownercountry = country THEN 0 ELSE cost END) AS cost FROM
(SELECT Roads.fromarea AS fromar, Roads.fromcountry AS fromcr, Roads.ownerpersonnummer,Roads.ownercountry,Persons.country,Persons.personnummer,
Roads.toarea AS destarea, Roads.tocountry AS destcountry, Roads.roadtax AS cost
FROM Persons,Roads 
WHERE ( Persons.personnummer <> '')
UNION 
SELECT Roads.toarea AS fromar, Roads.tocountry AS fromcr ,Roads.ownerpersonnummer,Roads.ownercountry, Persons.country,Persons.personnummer,
Roads.fromarea AS destarea, Roads.fromcountry AS destcountry, Roads.roadtax AS cost
FROM Persons,Roads 
WHERE (Persons.personnummer <> '')
) AS tmp
GROUP BY tmp.country,personnummer,destarea,destcountry,fromar,fromcr; 


CREATE VIEW AssetSummary AS
SELECT Persons.country,Persons.personnummer,Persons.budget, 
(SELECT COUNT(ownerpersonnummer) 
FROM Hotels WHERE ownerpersonnummer = personnummer AND ownercountry = country)*getval('hotelprice') +(SELECT COUNT(ownerpersonnummer) FROM Roads WHERE ownerpersonnummer = personnummer AND ownercountry = country)*getval('roadprice') AS assets,(SELECT 
COUNT(Hotels.ownerpersonnummer) FROM Hotels WHERE (ownercountry = country AND ownerpersonnummer = personnummer))*getval('hotelrefund')*getval('hotelprice') AS reclaimable
FROM Persons WHERE personnummer <> ''
;



CREATE FUNCTION insRoads() RETURNS TRIGGER AS $$
 BEGIN 
  IF EXISTS( 
  SELECT Roads.fromarea,Roads.toarea,Roads.fromcountry,Roads.tocountry,Roads.ownerpersonnummer,Roads.ownercountry 
  FROM Roads 
  WHERE ((fromarea = NEW.fromarea OR toarea = NEW.fromarea) AND (fromarea = NEW.toarea OR toarea = NEW.toarea) AND (fromcountry = NEW.fromcountry OR tocountry = NEW.fromcountry) AND(fromcountry = NEW.tocountry OR fromcountry = NEW.tocountry) AND (ownercountry=NEW.ownercountry AND ownerpersonnummer = NEW.ownerpersonnummer)))
    THEN RAISE EXCEPTION 'Road already exist for that owner';
  END IF;
  IF(NEW.ownerpersonnummer <> '') THEN
   IF NOT EXISTS(SELECT Persons.personnummer,Persons.country,Persons.locationarea,Persons.locationcountry 
    FROM Persons 
    WHERE (Persons.personnummer = NEW.ownerpersonnummer AND Persons.country = NEW.ownercountry AND (Persons.locationcountry = NEW.fromcountry OR Persons.locationcountry = NEW.tocountry) AND (Persons.locationarea = NEW.fromarea OR Persons.locationarea = NEW.toarea)))  
    THEN RAISE EXCEPTION 'owner not located in start or endpoint of road';
   ELSE
   UPDATE Persons
   SET budget = budget-getval('roadprice') WHERE (Persons.country = NEW.ownercountry AND Persons.personnummer = NEW.ownerpersonnummer); 
   RETURN NEW;
  END IF;
 ELSE
 RETURN NEW;
 END IF;
END;
$$ LANGUAGE 'plpgsql';


CREATE FUNCTION insHotel() RETURNS TRIGGER AS $$
 BEGIN
   IF EXISTS(SELECT ownerpersonnummer,ownercountry,locationcountry,locationname 
   FROM Hotels 
   WHERE(ownerpersonnummer = NEW.ownerpersonnummer AND ownercountry = NEW.ownercountry AND locationcountry = NEW.locationcountry AND locationname = NEW.locationname))
     THEN RAISE EXCEPTION 'Hotel already exist in that city for this owner';
   ELSE
     UPDATE Persons
     SET budget = budget - getval('hotelprice')
     WHERE (Persons.country = NEW.ownercountry AND Persons.personnummer = NEW.ownerpersonnummer);
     RETURN NEW;
   END IF;
  END;
$$ LANGUAGE 'plpgsql';


CREATE FUNCTION delHotel() RETURNS TRIGGER AS $$
 BEGIN
    UPDATE Persons
    SET budget = budget + getval('hotelprice')*getval('hotelrefund') 
    WHERE (Persons.personnummer = OLD.ownerpersonnummer AND Persons.country = OLD.ownercountry);
    RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';



CREATE FUNCTION updHotel() RETURNS TRIGGER AS $$
 BEGIN
   IF EXISTS(SELECT ownerpersonnummer,ownercountry,locationcountry,locationname 
   FROM Hotels 
   WHERE(ownerpersonnummer = NEW.ownerpersonnummer AND ownercountry = NEW.ownercountry AND locationcountry = NEW.locationcountry AND locationname = NEW.locationname))
     THEN RAISE EXCEPTION 'Hotel already exist in that city for this owner';
   END IF;
   IF(NEW.locationcountry <> OLD.locationcountry OR NEW.locationname <> OLD.locationname)
     THEN RAISE EXCEPTION 'Cannot move hotel';
   ELSE 
     RETURN NEW;
   END IF;
END;
$$ LANGUAGE 'plpgsql';


CREATE FUNCTION updRoads() RETURNS TRIGGER AS $$
 BEGIN
  IF(OLD.fromarea <> NEW.fromarea OR OLD.toarea <> NEW.toarea OR OLD.tocountry <> NEW.tocountry OR OLD.fromcountry <> NEW.fromcountry OR OLD.ownercountry <> NEW.ownercountry OR OLD.ownerpersonnummer <> NEW.ownerpersonnummer)
   THEN RAISE EXCEPTION 'Only roadtaxes can be changed';
  ELSE
   RETURN NEW;
  END IF;
 END;
$$ LANGUAGE 'plpgsql';

CREATE FUNCTION updPersons() RETURNS TRIGGER AS $$
 DECLARE mincost NUMERIC;
 BEGIN
 IF(NEW.locationcountry <> OLD.locationcountry OR NEW.locationarea <> OLD.locationarea) THEN
   IF NOT EXISTS (SELECT toarea,fromarea,tocountry,fromcountry FROM ROADS 
   WHERE((toarea = NEW.locationarea OR fromarea = NEW.locationarea) AND (tocountry = NEW.locationcountry OR fromcountry = NEW.locationcountry)
   AND (fromarea = OLD.locationarea OR toarea = OLD.locationarea) AND (fromcountry = OLD.locationcountry OR tocountry = OLD.locationcountry)))
     THEN RAISE EXCEPTION 'No road between areas';
   END IF;
   IF EXISTS (SELECT toarea,fromarea,tocountry,fromcountry,ownercountry,ownerpersonnummer FROM ROADS 
   WHERE((ownerpersonnummer = OLD.personnummer OR ownerpersonnummer = '') AND (ownercountry = OLD.country OR ownercountry = '') AND (toarea = NEW.locationarea OR fromarea = NEW.locationarea) AND (tocountry = NEW.locationcountry OR fromcountry = NEW.locationcountry)
   AND (fromarea = OLD.locationarea OR toarea = OLD.locationarea) AND (fromcountry = OLD.locationcountry OR tocountry = OLD.locationcountry)))
     THEN RETURN NEW;
   ELSE
    mincost:= (SELECT MIN(cost) FROM  NextMoves WHERE (destarea = NEW.locationarea AND destcountry = NEW.locationcountry AND area = OLD.locationarea AND country = OLD.locationcountry AND personnummer = NEW.personnummer AND personcountry = NEW.country));
    NEW.budget = OLD.budget-mincost;
    UPDATE Persons
    SET budget = budget+mincost
    WHERE ((Persons.personnummer,Persons.country) IN (SELECT ownerpersonnummer,ownercountry FROM Roads 
    WHERE(roadtax = mincost AND (fromarea = OLD.locationarea OR fromarea = NEW.locationarea) AND (fromcountry = OLD.locationcountry OR fromcountry = NEW.locationcountry) AND (tocountry = OLD.locationcountry OR tocountry = NEW.locationcountry) AND (toarea = OLD.locationarea OR toarea = NEW.locationarea))));
    RETURN NEW;
    END IF;
  ELSE
 RETURN NEW;
 END IF;
 END; 
$$ LANGUAGE 'plpgsql';

CREATE FUNCTION updPersons2() RETURNS TRIGGER AS $$
 BEGIN
 IF(OLD.locationcountry <> NEW.locationcountry OR OLD.locationarea <> NEW.locationarea) THEN
 IF((SELECT COUNT(Hotels.locationname) AS nbrHotels FROM Hotels WHERE(Hotels.locationname = NEW.locationarea AND Hotels.locationcountry = NEW.locationcountry)) > 0)
  THEN UPDATE Persons
   SET budget = budget - getval('cityvisit') WHERE ((Persons.personnummer = NEW.personnummer OR Persons.personnummer = NEW.personnummer) AND (Persons.country = OLD.country OR Persons.country = NEW.country));
  UPDATE Persons
   SET budget = (budget + getval('cityvisit')/(SELECT COUNT(Hotels.locationname) FROM Hotels 
   WHERE(Hotels.locationname = NEW.locationarea AND Hotels.locationcountry = NEW.locationcountry))) 
   WHERE ((Persons.personnummer,Persons.country) IN (SELECT ownerpersonnummer,ownercountry FROM Hotels WHERE(Hotels.locationname = NEW.locationarea AND Hotels.locationcountry = NEW.locationcountry)));
 END IF;
 IF EXISTS (SELECT visitbonus FROM Cities WHERE (country = NEW.locationcountry AND name = NEW.locationarea))
  THEN UPDATE Persons
   SET budget = budget+(SELECT visitbonus FROM Cities WHERE (country = NEW.locationcountry AND name = NEW.locationarea))
   WHERE (Persons.personnummer = NEW.personnummer AND Persons.country = NEW.country);
  UPDATE Cities
   SET visitbonus = 0 WHERE (country = NEW.locationcountry AND name = NEW.locationarea);
  RETURN NEW;
 ELSE 
 RETURN NEW;
 END IF;
ELSE
 RETURN NEW;
END IF;
END;
$$ LANGUAGE 'plpgsql';


CREATE TRIGGER updRoads
 BEFORE UPDATE on Roads
 FOR EACH ROW
 EXECUTE PROCEDURE updRoads();

CREATE TRIGGER insRoads
  BEFORE INSERT on Roads
  FOR EACH ROW
  EXECUTE PROCEDURE insRoads();

CREATE TRIGGER updPersons
 BEFORE UPDATE on Persons
 FOR EACH ROW
 EXECUTE PROCEDURE updPersons();

CREATE TRIGGER updPersons2
 AFTER UPDATE on Persons
 FOR EACH ROW
 EXECUTE PROCEDURE updPersons2();

CREATE TRIGGER insHotel
 BEFORE INSERT on Hotels
 FOR EACH ROW
 EXECUTE PROCEDURE insHotel();

CREATE TRIGGER delHotel
  AFTER DELETE on Hotels
  FOR EACH ROW
  EXECUTE PROCEDURE delHotel();

CREATE TRIGGER updHotel 
 BEFORE UPDATE on Hotels
 FOR EACH ROW
 EXECUTE PROCEDURE updHotel();















