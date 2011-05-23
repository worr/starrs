/* TRIGGER a_insert */
CREATE OR REPLACE FUNCTION "dns"."a_insert"() RETURNS TRIGGER AS $$
	DECLARE
		RowCount	INTEGER;
	BEGIN
		SELECT api.create_log_entry('database','DEBUG','Begin dns.a_insert');
		IF family(NEW."address")=4 THEN
			NEW."type" := 'A';
		ELSIF family(NEW."address")=6 THEN
			NEW."type" := 'AAAA';
		END IF;
		
		SELECT COUNT(*) INTO RowCount
		FROM "ip"."subnets"
		WHERE "ip"."subnets"."zone" = NEW."zone"
		AND NEW."address" << "ip"."subnets"."subnet";
			
		IF (RowCount < 1) THEN 
			SELECT api.create_log_entry('database','ERROR','Address/Zone mismatch');
			SELECT api.create_log_entry('database','ERROR',NEW);
			RAISE EXCEPTION 'IP address and DNS Zone do not match (%, %)',NEW."address",NEW."zone";
		END IF;
		
		RETURN NEW;
	END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."a_insert"() IS 'When creating a new A/AAAA record, automagically pick the record type';

/* TRIGGER a_update */
CREATE OR REPLACE FUNCTION "dns"."a_update"() RETURNS TRIGGER AS $$
DECLARE
	RowCount	INTEGER;
BEGIN
	SELECT api.create_log_entry('database','DEBUG','Begin dns.a_update');
	-- This function will auto fill in the DNS record type so you dont have to. It goes off of which IP family you are inserting.
	IF NEW."address" != OLD."address" THEN
		IF family(NEW."address")=4 THEN
			NEW."type" := 'A';
		ELSIF family(NEW."address")=6 THEN
			NEW."type" := 'AAAA';
		END IF;
		
		SELECT COUNT(*) INTO RowCount
		FROM "ip"."subnets"
		WHERE "ip"."subnets"."zone" = NEW."zone"
		AND NEW."address" << "ip"."subnets"."subnet";
			
		IF (RowCount < 1) THEN 
			SELECT api.create_log_entry('database','ERROR','Address/Zone mismatch');
			SELECT api.create_log_entry('database','ERROR',NEW);
			RAISE EXCEPTION 'IP address and DNS Zone do not match (%, %)',NEW."address",NEW."zone";
		END IF;
	END IF;
	
	IF NEW."zone" != OLD."zone" THEN
		SELECT COUNT(*) INTO RowCount
		FROM "ip"."subnets"
		WHERE "ip"."subnets"."zone" = NEW."zone"
		AND NEW."address" << "ip"."subnets"."subnet";
			
		IF (RowCount < 1) THEN 
			SELECT api.create_log_entry('database','ERROR','Address/Zone mismatch');
			SELECT api.create_log_entry('database','ERROR',NEW);
			RAISE EXCEPTION 'IP address and DNS Zone do not match (%, %)',NEW."address",NEW."zone";
		END IF;
	END IF;

	NEW."date_modified" := current_timestamp;
	RETURN NEW;
END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."a_update"() IS 'When altering a A/AAAA record, automagically pick the record type.';

/* TRIGGER - pointers_insert */
CREATE OR REPLACE FUNCTION "dns"."pointer_insert"() RETURNS TRIGGER AS $$
	DECLARE
		RowCount	INTEGER;
	BEGIN
		SELECT api.create_log_entry('database','DEBUG','Begin dns.pointer_insert');
		-- Check if alias exists in A table
		SELECT COUNT(*) INTO RowCount
		FROM "dns"."a"
		WHERE "dns"."a"."fqdn" = NEW."alias";
		
		IF (RowCount > 0) THEN
			SELECT api.create_log_entry('database','ERROR','Alias name already exists');
			SELECT api.create_log_entry('database','ERROR',NEW);
			RAISE EXCEPTION 'Alias name (%) already exists',NEW."alias";
		END IF;
		SELECT api.create_log_entry('database','INFO','Creating new alias');
		RETURN NEW;
	END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."pointer_insert"() IS 'Check if the alias already exists as an address record';

/* TRIGGER - pointers_update */
CREATE OR REPLACE FUNCTION "dns"."pointer_update"() RETURNS TRIGGER AS $$
	DECLARE
		RowCount	INTEGER;
	BEGIN
		SELECT api.create_log_entry('database','DEBUG','Begin dns.pointer_update');
		IF NEW."alias" != OLD."alias" THEN
			-- Check if alias exists in A table
			SELECT COUNT(*) INTO RowCount
			FROM "dns"."a"
			WHERE "dns"."a"."fqdn" = NEW."alias";
			
			IF (RowCount > 0) THEN
				SELECT api.create_log_entry('database','ERROR','Alias name already exists');
				SELECT api.create_log_entry('database','ERROR',NEW);
				RAISE EXCEPTION 'Alias name (%) already exists',NEW."alias";
			END IF;
		END IF;

		NEW."date_modified" := current_timestamp;
		SELECT api.create_log_entry('database','INFO','Modifying alias');
		RETURN NEW;
	END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."pointer_update"() IS 'Check if the new alias already exists as an address record';

/* TRIGGER - ns_insert */
CREATE OR REPLACE FUNCTION "dns"."ns_insert" RETURNS TRIGGER AS $$
	DECLARE
		RowCount	INTEGER;
	BEGIN
		SELECT api.create_log_entry('database','INFO','Begin dns.ns_insert');
		-- Check for existing primary NS for zone
		SELECT COUNT(*) INTO RowCount
		FROM "dns"."ns"
		WHERE "dns"."ns"."zone" = NEW."zone" AND "dns"."ns"."isprimary" = TRUE;
		
		IF NEW."isprimary" = TRUE AND RowCount > 0 THEN
			SELECT api.create_log_entry('database','ERROR','Primary NS for zone already exists');
			SELECT api.create_log_entry('database','ERROR',NEW);
			RAISE EXCEPTION 'Primary NS for zone already exists';
		ELSIF NEW."isprimary" = FALSE AND RowCount = 0 THEN
			SELECT api.create_log_entry('database','ERROR','No primary NS for zone already exists and this is not one');
			SELECT api.create_log_entry('database','ERROR',NEW);
			RAISE EXCEPTION 'No primary NS for zone exists, and this is not primary. You must specify a primary NS for a zone';
		END IF;

		SELECT api.create_log_entry('database','INFO','Creating new NS');
		RETURN NEW;
	END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."ns_insert"() IS 'Check that there is only one primary NS registered for a given zone';

/* TRIGGER - ns_update */
CREATE OR REPLACE FUNCTION "dns"."ns_update" RETURNS TRIGGER AS $$
	DECLARE
		RowCount	INTEGER;
	BEGIN
		-- Check for existing primary NS for zone
		IF NEW."zone" != OLD."zone_id" THEN
			SELECT COUNT(*) INTO RowCount
			FROM "dns"."ns"
			WHERE "dns"."ns"."zone" = NEW."zone_id" AND "dns"."ns"."isprimary" = TRUE;
			
			IF NEW."isprimary" = TRUE AND RowCount > 0 THEN
				SELECT api.create_log_entry('database','ERROR','Primary NS for zone already exists');
				SELECT api.create_log_entry('database','ERROR',NEW);
				RAISE EXCEPTION 'Primary NS for zone already exists';
			ELSIF NEW."isprimary" = FALSE AND RowCount = 0 THEN
				SELECT api.create_log_entry('database','ERROR','No primary NS for zone already exists and this is not one');
				SELECT api.create_log_entry('database','ERROR',NEW);
				RAISE EXCEPTION 'No primary NS for zone exists, and this is not primary. You must specify a primary NS for a zone';
			END IF;
		END IF;

		SELECT api.create_log_entry('database','INFO','Modifying NS');
		NEW."date_modified" := current_timestamp;
		RETURN NEW;
	END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."ns_update"() IS 'Check that the new settings provide for a primary nameserver for the zone';

/* Trigger - dns_autopopulate_address */
CREATE OR REPLACE FUNCTION "dns"."dns_autopopulate_address"() RETURNS TRIGGER AS $$
	BEGIN
		SELECT "address" INTO NEW."address"
		FROM "dns"."a"
		WHERE "dns"."a"."hostname" = NEW."hostname"
		AND "dns"."a"."zone" = NEW."zone";
		RETURN NEW;
	END;
$$ LANGUAGE 'plpgsql';
COMMENT ON FUNCTION "dns"."dns_autopopulate_address"() IS 'Fill in the address portion of the foreign key relationship';