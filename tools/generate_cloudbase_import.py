#!/usr/bin/env python3
"""Generate a transaction-safe CloudBase import SQL from Supabase CSV exports.

The generated SQL contains production customer data and must stay gitignored.
Passwords and access tokens are never accepted or written by this tool.
"""

from __future__ import annotations

import argparse
import csv
import json
from collections import Counter
from pathlib import Path
from typing import Callable, Iterable


FILES = {
    "customers": "customers_rows.csv",
    "storage_big_item_options": "storage_big_item_options_rows.csv",
    "storage_small_item_options": "storage_small_item_options_rows.csv",
    "storage_records": "storage_records_rows.csv",
    "consumption_records": "consumption_records_rows.csv",
    "inventory_purchase_records": "inventory_purchase_records_rows.csv",
    "inventory_supplementary_in_records": "inventory_supplementary_in_records_rows.csv",
    "inventory_consumption_records": "inventory_consumption_records_rows.csv",
}

REQUIRED_COLUMNS = {
    "customers": [
        "name", "phone", "lunar_birthday", "solar_birthday", "zodiac",
        "age", "address", "life_number", "symptoms", "created_at", "owner_id",
    ],
    "storage_big_item_options": ["id", "name", "owner_id"],
    "storage_small_item_options": ["id", "name", "storage_big_item_id", "owner_id"],
    "storage_records": [
        "id", "code", "customer_name", "storage_big_items",
        "storage_small_item_ids", "amount", "total_count", "storage_date",
        "remark", "created_at", "owner_id",
    ],
    "consumption_records": [
        "id", "code", "consumption_date", "storage_record_id",
        "consumption_project_id", "signature_url", "remark", "created_at",
        "consumption_project_ids", "owner_id",
    ],
    "inventory_purchase_records": [
        "id", "code", "purchase_date", "storage_big_items",
        "storage_small_item_ids", "quantities", "total_amount", "remark",
        "created_at", "owner_id", "occurred_at", "occurred_at_is_estimated",
        "voided_at", "voided_by", "void_reason",
    ],
    "inventory_supplementary_in_records": [
        "id", "supplement_date", "storage_small_item_id", "quantity", "remark",
        "created_at", "owner_id", "occurred_at", "occurred_at_is_estimated",
        "voided_at", "voided_by", "void_reason",
    ],
    "inventory_consumption_records": [
        "id", "consumption_date", "storage_small_item_id", "quantity", "remark",
        "created_at", "source_storage_record_id", "owner_id", "occurred_at",
        "occurred_at_is_estimated", "voided_at", "voided_by", "void_reason",
    ],
}


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8-sig") as handle:
        reader = csv.DictReader(handle)
        rows = list(reader)
        if reader.fieldnames is None:
            raise ValueError(f"{path.name}: missing header")
        return rows


def sql_text(value: str | None) -> str:
    if value is None or value == "":
        return "NULL"
    if "\x00" in value:
        raise ValueError("NUL bytes are not supported in PostgreSQL text")
    return "'" + value.replace("'", "''") + "'"


def sql_int(value: str | None) -> str:
    if value is None or value == "":
        return "NULL"
    return str(int(value))


def sql_number(value: str | None) -> str:
    if value is None or value == "":
        return "NULL"
    float(value)
    return value


def sql_bool(value: str | None) -> str:
    if value is None or value == "":
        return "NULL"
    normalized = value.strip().lower()
    if normalized not in {"true", "false"}:
        raise ValueError(f"Invalid boolean: {value}")
    return normalized


def parse_json_array(value: str | None) -> list[object]:
    if value is None or value == "":
        return []
    parsed = json.loads(value)
    if not isinstance(parsed, list):
        raise ValueError(f"Expected JSON array, got: {value}")
    return parsed


def sql_int_array(value: str | None) -> str:
    values = [str(int(item)) for item in parse_json_array(value)]
    return "ARRAY[" + ",".join(values) + "]::integer[]"


def sql_text_array(value: str | None) -> str:
    values = [sql_text(str(item)) for item in parse_json_array(value)]
    return "ARRAY[" + ",".join(values) + "]::text[]"


def write_insert(
    output: list[str],
    table: str,
    columns: list[str],
    rows: Iterable[dict[str, str]],
    render: Callable[[dict[str, str]], list[str]],
    batch_size: int = 100,
) -> None:
    rendered = [render(row) for row in rows]
    for start in range(0, len(rendered), batch_size):
        batch = rendered[start:start + batch_size]
        output.append(f"INSERT INTO {table} ({', '.join(columns)}) VALUES")
        output.append(",\n".join("  (" + ", ".join(values) + ")" for values in batch) + ";")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source-dir", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--old-production-owner", required=True)
    parser.add_argument("--old-demo-owner", required=True)
    parser.add_argument("--new-production-owner", required=True)
    parser.add_argument("--new-demo-owner", required=True)
    args = parser.parse_args()

    owner_map = {
        args.old_production_owner: args.new_production_owner,
        args.old_demo_owner: args.new_demo_owner,
    }
    if len(owner_map) != 2 or len(set(owner_map.values())) != 2:
        raise ValueError("Production and demo owners must be distinct")

    data: dict[str, list[dict[str, str]]] = {}
    for table, filename in FILES.items():
        path = args.source_dir / filename
        if not path.is_file():
            raise FileNotFoundError(path)
        rows = read_csv(path)
        actual = list(rows[0].keys()) if rows else REQUIRED_COLUMNS[table]
        if actual != REQUIRED_COLUMNS[table]:
            raise ValueError(f"{filename}: schema mismatch: {actual}")
        data[table] = rows

    observed_owners = {
        row["owner_id"]
        for rows in data.values()
        for row in rows
        if row.get("owner_id")
    }
    if observed_owners != set(owner_map):
        raise ValueError(f"Unexpected owner set: {sorted(observed_owners)}")

    for table, rows in data.items():
        key = "name" if table == "customers" else "id"
        values = [row[key] for row in rows]
        if any(value == "" for value in values) or len(values) != len(set(values)):
            raise ValueError(f"{table}: blank or duplicate primary key")

    source_big = {int(row["id"]): row for row in data["storage_big_item_options"]}
    source_small_ids = {int(row["id"]) for row in data["storage_small_item_options"]}
    missing_purchase_refs = 0
    for row in data["inventory_purchase_records"]:
        big_items = parse_json_array(row["storage_big_items"])
        small_ids = [int(item) for item in parse_json_array(row["storage_small_item_ids"])]
        quantities = [int(item) for item in parse_json_array(row["quantities"])]
        if not small_ids or len(big_items) != len(small_ids) or len(small_ids) != len(quantities):
            raise ValueError(f"Purchase {row['id']}: array lengths are invalid")
        missing_purchase_refs += sum(item not in source_small_ids for item in small_ids)
    if missing_purchase_refs != 10:
        raise ValueError(
            f"Expected 10 known legacy missing purchase item refs, got {missing_purchase_refs}"
        )

    def mapped_owner(row: dict[str, str]) -> str:
        return owner_map[row["owner_id"]]

    def mapped_actor(value: str) -> str:
        if value == "":
            return "NULL"
        if value not in owner_map:
            raise ValueError(f"Unknown voided_by owner: {value}")
        return sql_text(owner_map[value])

    out: list[str] = [
        "BEGIN;",
        "SET LOCAL lock_timeout = '5s';",
        "SET LOCAL statement_timeout = '5min';",
        "SET LOCAL standard_conforming_strings = on;",
        "DO $$",
        "DECLARE v_existing bigint;",
        "BEGIN",
        "  SELECT",
        "    (SELECT count(*) FROM customers) +",
        "    (SELECT count(*) FROM storage_small_item_options) +",
        "    (SELECT count(*) FROM storage_records) +",
        "    (SELECT count(*) FROM consumption_records) +",
        "    (SELECT count(*) FROM inventory_purchase_records) +",
        "    (SELECT count(*) FROM inventory_supplementary_in_records) +",
        "    (SELECT count(*) FROM inventory_consumption_records)",
        "  INTO v_existing;",
        "  IF v_existing <> 0 THEN",
        "    RAISE EXCEPTION '导入已停止：目标业务表不是空库，共有 % 条记录', v_existing;",
        "  END IF;",
        f"  IF (SELECT count(*) FROM storage_big_item_options WHERE owner_id = {sql_text(args.new_production_owner)}) <> 5 THEN",
        "    RAISE EXCEPTION '导入已停止：正式账号默认大项不是 5 条';",
        "  END IF;",
        f"  IF (SELECT count(*) FROM storage_big_item_options WHERE owner_id = {sql_text(args.new_demo_owner)}) <> 5 THEN",
        "    RAISE EXCEPTION '导入已停止：体验账号默认大项不是 5 条';",
        "  END IF;",
        f"  IF NOT EXISTS (SELECT 1 FROM auth.users WHERE sub = {sql_text(args.new_production_owner)})",
        f"    OR NOT EXISTS (SELECT 1 FROM auth.users WHERE sub = {sql_text(args.new_demo_owner)}) THEN",
        "    RAISE EXCEPTION '导入已停止：CloudBase 目标账号不存在';",
        "  END IF;",
        "END $$;",
    ]

    write_insert(
        out,
        "storage_big_item_options",
        ["owner_id", "name"],
        data["storage_big_item_options"],
        lambda row: [sql_text(mapped_owner(row)), sql_text(row["name"])],
    )
    out[-1] = out[-1][:-1] + " ON CONFLICT (owner_id, name) DO NOTHING;"

    write_insert(
        out,
        "customers",
        REQUIRED_COLUMNS["customers"],
        data["customers"],
        lambda row: [
            sql_text(row["name"]), sql_text(row["phone"]), sql_text(row["lunar_birthday"]),
            sql_text(row["solar_birthday"]), sql_text(row["zodiac"]), sql_int(row["age"]),
            sql_text(row["address"]), sql_int(row["life_number"]), sql_text(row["symptoms"]),
            sql_text(row["created_at"]), sql_text(mapped_owner(row)),
        ],
    )

    def render_small(row: dict[str, str]) -> list[str]:
        big_id = row["storage_big_item_id"]
        if big_id == "":
            mapped_big = "NULL"
        else:
            source = source_big[int(big_id)]
            if source["owner_id"] != row["owner_id"]:
                raise ValueError(f"Small item {row['id']}: big item owner mismatch")
            mapped_big = (
                "(SELECT id FROM storage_big_item_options WHERE owner_id = "
                + sql_text(mapped_owner(row))
                + " AND name = " + sql_text(source["name"]) + ")"
            )
        return [sql_int(row["id"]), sql_text(row["name"]), mapped_big, sql_text(mapped_owner(row))]

    write_insert(
        out,
        "storage_small_item_options",
        REQUIRED_COLUMNS["storage_small_item_options"],
        data["storage_small_item_options"],
        render_small,
    )

    write_insert(
        out,
        "storage_records",
        REQUIRED_COLUMNS["storage_records"],
        data["storage_records"],
        lambda row: [
            sql_int(row["id"]), sql_text(row["code"]), sql_text(row["customer_name"]),
            sql_text_array(row["storage_big_items"]), sql_int_array(row["storage_small_item_ids"]),
            sql_number(row["amount"]), sql_int(row["total_count"]), sql_text(row["storage_date"]),
            sql_text(row["remark"]), sql_text(row["created_at"]), sql_text(mapped_owner(row)),
        ],
    )

    write_insert(
        out,
        "consumption_records",
        REQUIRED_COLUMNS["consumption_records"],
        data["consumption_records"],
        lambda row: [
            sql_int(row["id"]), sql_text(row["code"]), sql_text(row["consumption_date"]),
            sql_int(row["storage_record_id"]), sql_int(row["consumption_project_id"]),
            sql_text(row["signature_url"]), sql_text(row["remark"]), sql_text(row["created_at"]),
            sql_int_array(row["consumption_project_ids"]), sql_text(mapped_owner(row)),
        ],
    )

    out.extend([
        "ALTER TABLE inventory_purchase_records DISABLE TRIGGER inventory_purchase_validate_owned_items;",
        "ALTER TABLE inventory_purchase_records DISABLE TRIGGER inventory_purchase_audit_guard;",
        "ALTER TABLE inventory_supplementary_in_records DISABLE TRIGGER inventory_supp_in_audit_guard;",
        "ALTER TABLE inventory_consumption_records DISABLE TRIGGER inventory_consumption_audit_guard;",
    ])

    write_insert(
        out,
        "inventory_purchase_records",
        REQUIRED_COLUMNS["inventory_purchase_records"],
        data["inventory_purchase_records"],
        lambda row: [
            sql_int(row["id"]), sql_text(row["code"]), sql_text(row["purchase_date"]),
            sql_text_array(row["storage_big_items"]), sql_int_array(row["storage_small_item_ids"]),
            sql_int_array(row["quantities"]), sql_number(row["total_amount"]), sql_text(row["remark"]),
            sql_text(row["created_at"]), sql_text(mapped_owner(row)), sql_text(row["occurred_at"]),
            sql_bool(row["occurred_at_is_estimated"]), sql_text(row["voided_at"]),
            mapped_actor(row["voided_by"]), sql_text(row["void_reason"]),
        ],
    )

    write_insert(
        out,
        "inventory_supplementary_in_records",
        REQUIRED_COLUMNS["inventory_supplementary_in_records"],
        data["inventory_supplementary_in_records"],
        lambda row: [
            sql_int(row["id"]), sql_text(row["supplement_date"]), sql_int(row["storage_small_item_id"]),
            sql_int(row["quantity"]), sql_text(row["remark"]), sql_text(row["created_at"]),
            sql_text(mapped_owner(row)), sql_text(row["occurred_at"]),
            sql_bool(row["occurred_at_is_estimated"]), sql_text(row["voided_at"]),
            mapped_actor(row["voided_by"]), sql_text(row["void_reason"]),
        ],
    )

    write_insert(
        out,
        "inventory_consumption_records",
        REQUIRED_COLUMNS["inventory_consumption_records"],
        data["inventory_consumption_records"],
        lambda row: [
            sql_int(row["id"]), sql_text(row["consumption_date"]), sql_int(row["storage_small_item_id"]),
            sql_int(row["quantity"]), sql_text(row["remark"]), sql_text(row["created_at"]),
            sql_int(row["source_storage_record_id"]), sql_text(mapped_owner(row)),
            sql_text(row["occurred_at"]), sql_bool(row["occurred_at_is_estimated"]),
            sql_text(row["voided_at"]), mapped_actor(row["voided_by"]), sql_text(row["void_reason"]),
        ],
    )

    out.extend([
        "ALTER TABLE inventory_purchase_records ENABLE TRIGGER inventory_purchase_validate_owned_items;",
        "ALTER TABLE inventory_purchase_records ENABLE TRIGGER inventory_purchase_audit_guard;",
        "ALTER TABLE inventory_supplementary_in_records ENABLE TRIGGER inventory_supp_in_audit_guard;",
        "ALTER TABLE inventory_consumption_records ENABLE TRIGGER inventory_consumption_audit_guard;",
        "SELECT setval(pg_get_serial_sequence('storage_big_item_options', 'id'), (SELECT max(id) FROM storage_big_item_options), true);",
        "SELECT setval(pg_get_serial_sequence('storage_small_item_options', 'id'), (SELECT max(id) FROM storage_small_item_options), true);",
        "SELECT setval(pg_get_serial_sequence('storage_records', 'id'), (SELECT max(id) FROM storage_records), true);",
        "SELECT setval(pg_get_serial_sequence('consumption_records', 'id'), (SELECT max(id) FROM consumption_records), true);",
        "SELECT setval(pg_get_serial_sequence('inventory_purchase_records', 'id'), (SELECT max(id) FROM inventory_purchase_records), true);",
        "SELECT setval(pg_get_serial_sequence('inventory_supplementary_in_records', 'id'), (SELECT max(id) FROM inventory_supplementary_in_records), true);",
        "SELECT setval(pg_get_serial_sequence('inventory_consumption_records', 'id'), (SELECT max(id) FROM inventory_consumption_records), true);",
        "SELECT setval('storage_code_seq', (SELECT max(substring(code FROM 3)::integer) FROM storage_records WHERE code ~ '^CZ[0-9]+$'), true);",
        "SELECT setval('consumption_code_seq', (SELECT max(substring(code FROM 3)::integer) FROM consumption_records WHERE code ~ '^XF[0-9]+$'), true);",
        "SELECT setval('inventory_purchase_code_seq', (SELECT max(substring(code FROM 3)::integer) FROM inventory_purchase_records WHERE code ~ '^JH[0-9]+$'), true);",
        "DO $$",
        "DECLARE",
        "  v_missing_purchase_refs bigint;",
        "BEGIN",
    ])

    for table, rows in data.items():
        if table == "storage_big_item_options":
            continue
        counts = Counter(mapped_owner(row) for row in rows)
        for owner, expected in sorted(counts.items()):
            out.extend([
                f"  IF (SELECT count(*) FROM {table} WHERE owner_id = {sql_text(owner)}) <> {expected} THEN",
                f"    RAISE EXCEPTION '导入校验失败：{table} 账号记录数不等于 {expected}';",
                "  END IF;",
            ])

    big_counts = Counter(mapped_owner(row) for row in data["storage_big_item_options"])
    for owner, expected in sorted(big_counts.items()):
        out.extend([
            f"  IF (SELECT count(*) FROM storage_big_item_options WHERE owner_id = {sql_text(owner)}) <> {expected} THEN",
            f"    RAISE EXCEPTION '导入校验失败：storage_big_item_options 账号记录数不等于 {expected}';",
            "  END IF;",
        ])

    out.extend([
        "  SELECT count(*) INTO v_missing_purchase_refs",
        "  FROM inventory_purchase_records p",
        "  CROSS JOIN LATERAL unnest(p.storage_small_item_ids) AS ids(item_id)",
        "  LEFT JOIN storage_small_item_options s",
        "    ON s.owner_id = p.owner_id AND s.id = ids.item_id",
        "  WHERE s.id IS NULL;",
        "  IF v_missing_purchase_refs <> 10 THEN",
        "    RAISE EXCEPTION '导入校验失败：历史已删除小项引用应为 10，实际为 %', v_missing_purchase_refs;",
        "  END IF;",
        "  IF EXISTS (",
        "    SELECT 1 FROM inventory_purchase_records",
        "    WHERE cardinality(storage_small_item_ids) = 0",
        "      OR cardinality(storage_big_items) <> cardinality(storage_small_item_ids)",
        "      OR cardinality(storage_small_item_ids) <> cardinality(quantities)",
        "  ) THEN",
        "    RAISE EXCEPTION '导入校验失败：进货数组未对齐';",
        "  END IF;",
        "  IF EXISTS (",
        "    SELECT 1 FROM inventory_purchase_records",
        "    WHERE (occurred_at AT TIME ZONE 'Asia/Shanghai')::date <> purchase_date",
        "  ) OR EXISTS (",
        "    SELECT 1 FROM inventory_supplementary_in_records",
        "    WHERE (occurred_at AT TIME ZONE 'Asia/Shanghai')::date <> supplement_date",
        "  ) OR EXISTS (",
        "    SELECT 1 FROM inventory_consumption_records",
        "    WHERE (occurred_at AT TIME ZONE 'Asia/Shanghai')::date <> consumption_date",
        "  ) THEN",
        "    RAISE EXCEPTION '导入校验失败：库存业务日期与发生时间不一致';",
        "  END IF;",
        "  IF EXISTS (",
        "    SELECT 1 FROM pg_trigger",
        "    WHERE tgname IN (",
        "      'inventory_purchase_validate_owned_items',",
        "      'inventory_purchase_audit_guard',",
        "      'inventory_supp_in_audit_guard',",
        "      'inventory_consumption_audit_guard'",
        "    ) AND tgenabled <> 'O'",
        "  ) THEN",
        "    RAISE EXCEPTION '导入校验失败：库存保护触发器未恢复';",
        "  END IF;",
        "END $$;",
        "COMMIT;",
    ])

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text("\n\n".join(out) + "\n", encoding="utf-8")
    print(json.dumps({
        "output": str(args.output),
        "bytes": args.output.stat().st_size,
        "rows": {table: len(rows) for table, rows in data.items()},
        "known_missing_purchase_item_refs": missing_purchase_refs,
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
