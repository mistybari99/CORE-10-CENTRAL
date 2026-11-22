-- Disposable test only. Requires buyer, reviewer, site, location, supplier and item psql variables.
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',:'grn_buyer')::text,false);
SELECT (core10.procurement_save_po_v1(:grn_business,NULL,:grn_site,:grn_supplier,
 jsonb_build_array(jsonb_build_object('item_id',:grn_item,'quantity',100,'unit_price',50)),
 NULL,NULL,0,:'grn_key'||'_po')->>'po_id')::bigint AS po_id \gset
SELECT set_config('request.jwt.claims',jsonb_build_object('sub',:'grn_reviewer')::text,false);
SELECT core10.procurement_advance_po_v1(:po_id,'approve',1,:'grn_key'||'_approve');
SELECT (core10.procurement_receive_v1(:po_id,:grn_location,jsonb_build_array(jsonb_build_object(
 'line_no',1,'quantity',60,'lot_code',:'grn_key','manufactured_on',current_date-1,'expires_on',current_date+30
 )),NULL,:'grn_key'||'_receive')->>'grn_id')::bigint AS grn_id \gset
SELECT core10.procurement_inspect_v1(:grn_id,'[{"line_no":1,"accepted_qty":58}]',1,:'grn_key'||'_qc');
SELECT core10.procurement_post_grn_v1(:grn_id,2,:'grn_key'||'_post') AS posted_grn \gset
SELECT (:'posted_grn'::jsonb->'lines'->0->>'lot_id')::bigint AS lot_id,
 (:'posted_grn'::jsonb->'lines'->0->>'stock_movement_id')::bigint AS movement_id \gset
