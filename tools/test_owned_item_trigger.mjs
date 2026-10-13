const { PGlite } = await import(process.env.PGLITE_MODULE || '@electric-sql/pglite');
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const db = new PGlite();
await db.exec(`CREATE TABLE storage_small_item_options(id int PRIMARY KEY,owner_id uuid NOT NULL);
CREATE TABLE storage_records(id serial PRIMARY KEY,owner_id uuid NOT NULL,storage_small_item_ids int[]);
CREATE TABLE inventory_purchase_records(id serial PRIMARY KEY,owner_id uuid NOT NULL,storage_big_items text[],storage_small_item_ids int[],quantities int[]);
INSERT INTO storage_small_item_options VALUES (1,'11111111-1111-1111-1111-111111111111'),(2,'22222222-2222-2222-2222-222222222222');`);
await db.exec(`CREATE FUNCTION validate_owned_small_item_array() RETURNS TRIGGER
LANGUAGE plpgsql AS $$ BEGIN
  IF TG_TABLE_NAME = 'inventory_purchase_records' AND
     cardinality(NEW.quantities) <> cardinality(NEW.storage_small_item_ids) THEN
    RAISE EXCEPTION 'misaligned purchase';
  END IF;
  RETURN NEW;
END $$;`);
await db.exec(`CREATE TRIGGER storage_records_validate_owned_items BEFORE INSERT OR UPDATE OF owner_id,storage_small_item_ids ON storage_records FOR EACH ROW EXECUTE FUNCTION validate_owned_small_item_array();
CREATE TRIGGER inventory_purchase_validate_owned_items BEFORE INSERT OR UPDATE OF owner_id,storage_big_items,storage_small_item_ids,quantities ON inventory_purchase_records FOR EACH ROW EXECUTE FUNCTION validate_owned_small_item_array();`);
const owner="'11111111-1111-1111-1111-111111111111'";
try { await db.exec(`INSERT INTO storage_records(owner_id,storage_small_item_ids) VALUES (${owner},ARRAY[1]);`); throw Error('bug did not reproduce'); }
catch(e){if(e.code!=='42703')throw e; console.log('REPRODUCED 42703 missing quantities');}
await db.exec(fs.readFileSync(path.join(root, 'docs/supabase_migrations/018_fix_owned_item_trigger.sql'),'utf8'));
await db.exec(`INSERT INTO storage_records(owner_id,storage_small_item_ids) VALUES (${owner},ARRAY[1]); UPDATE storage_records SET storage_small_item_ids=ARRAY[1];`);
console.log('PASS storage insert and update');
async function blocked(sql,label){try{await db.exec(sql);}catch(e){if(e.code==='P0001'){console.log('PASS blocked '+label);return;}throw e;}throw Error('unsafe write accepted '+label);}
await blocked(`INSERT INTO storage_records(owner_id,storage_small_item_ids) VALUES (${owner},ARRAY[2]);`,'cross-account storage');
await blocked(`INSERT INTO storage_records(owner_id,storage_small_item_ids) VALUES (${owner},ARRAY[999]);`,'missing option storage');
await db.exec(`INSERT INTO inventory_purchase_records(owner_id,storage_big_items,storage_small_item_ids,quantities) VALUES (${owner},ARRAY['A'],ARRAY[1],ARRAY[3]);`);
console.log('PASS valid purchase');
await blocked(`INSERT INTO inventory_purchase_records(owner_id,storage_big_items,storage_small_item_ids,quantities) VALUES (${owner},ARRAY['A'],ARRAY[1],ARRAY[1,2]);`,'misaligned purchase');
await blocked(`INSERT INTO inventory_purchase_records(owner_id,storage_big_items,storage_small_item_ids,quantities) VALUES (${owner},ARRAY['A'],ARRAY[2],ARRAY[1]);`,'cross-account purchase');
await db.exec('DELETE FROM storage_small_item_options WHERE id=1; UPDATE inventory_purchase_records SET quantities=quantities;');
console.log('PASS historical purchase unchanged arrays');
await blocked('UPDATE inventory_purchase_records SET quantities=ARRAY[4];','historical purchase changed quantity');
await db.close();
