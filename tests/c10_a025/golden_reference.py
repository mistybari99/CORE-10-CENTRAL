#!/usr/bin/env python3
"""C10-A025 INDEPENDENT golden reference.
Re-implements every model formula with python Fractions (no shared code with the JS engine) and produces
golden.json (inputs + expected outputs). `--write` regenerates it, `--check` fails if the committed file differs.
The JS test (golden.test.js) then verifies the engine against the committed numbers, so two independent
implementations must agree. Rounding: half away from zero at the display places used by the engine."""
import json, sys, math
from fractions import Fraction as F
from decimal import Decimal, getcontext
getcontext().prec = 80

def f(x): return F(str(x))
def q(x, p=2):
    x = F(x); s = 1 if x >= 0 else -1; x = abs(x) * 10**p
    n = x.numerator // x.denominator; r = x - n
    if r * 2 >= 1: n += 1
    v = s * n
    out = f"{abs(v)//10**p}" + (("." + str(abs(v) % 10**p).zfill(p)) if p else "")
    return ("-" if v < 0 and v != 0 else "") + out
def sqrtq(x, p):
    d = Decimal(x.numerator) / Decimal(x.denominator); return q(F(str(d.sqrt())), p)
def ceil(x): return -((-x.numerator) // x.denominator)
def conv(qty, a, b):
    T = {"kg": 1000, "g": 1, "lb": F("453.59237"), "l": 1000, "ml": 1, "piece": 1, "dozen": 12, "bag50kg": 50000}
    return f(qty) * F(T[a]) / F(T[b])
def npv(r, cfs): return sum(c / (1 + r) ** t for t, c in enumerate(cfs))
def loan(P, apr, n, method):
    r = f(apr) / 100 / 12; P = f(q(P)); bal = P; rows = []
    pmt = None
    if method == "amortized":
        pmt = f(q(P / n if r == 0 else P * r * (1 + r) ** n / ((1 + r) ** n - 1)))
    fp = f(q(P / n))
    for m in range(1, n + 1):
        i = f(q(bal * r))
        pr = (pmt - i) if method == "amortized" else (fp if method == "fixed_principal" else (bal if m == n else F(0)))
        if m == n or pr > bal: pr = bal
        rows.append((i, pr, pr + i)); bal -= pr
    return rows
def alloc(total, w, p=2):
    t = f(q(total, p)); W = sum(map(f, w)); u = 10**p; tu = int(t * u)
    raw = [tu * f(x) for x in w]; base = [int(r // W) for r in raw]; rem = sorted(range(len(w)), key=lambda i: (-(raw[i] % W), i))
    left = tu - sum(base)
    for k in range(left): base[rem[k]] += 1
    return [F(b, u) for b in base]

def m01(i, v2):
    p, c = f(i["selling_price"]), f(i["unit_cost"]); d = f(i.get("discount_pct", 0)) / 100; w = f(i.get("waste_pct", 0)) / 100; u = f(i.get("units", 1))
    fee = f(i.get("channel_fee_pct", 0)) / 100 if v2 else F(0)
    net = p * (1 - d); eff = c / (1 - w); cf = net * fee; con = net - cf - eff
    o = {"net_price": q(net), "effective_unit_cost": q(eff), "contribution_per_unit": q(con), "total_contribution": q(con * u)}
    o["margin_on_revenue_pct"] = q(con / net * 100, 4) if net > 0 else None
    o["markup_on_cost_pct"] = q(con / eff * 100, 4) if eff > 0 else None
    o["max_discount_before_loss_pct"] = q((1 - eff / (p * (1 - fee))) * 100, 4) if v2 else q((p - eff) / p * 100, 4)
    return o
def m02(i):
    cm = f(i["unit_price"]) - f(i["variable_cost_per_unit"]); need = f(i["fixed_costs"]) + f(i.get("target_profit", 0)); o = {"contribution_per_unit": q(cm)}
    if cm <= 0: o.update(break_even_units=None, break_even_revenue=None); return o
    u = need / cm; o.update(break_even_units=q(u, 4), break_even_units_rounded_up=str(ceil(u)), break_even_revenue=q(u * f(i["unit_price"]))); return o
def m03(i):
    gp = f(i["revenue"]) - f(i["cogs"]); dep = f(i.get("depreciation", 0)); eb = gp - f(i["operating_expenses"]) - dep; pbt = eb - f(i.get("interest_expense", 0))
    o = {"gross_profit": q(gp), "operating_profit": q(eb), "profit_before_tax": q(pbt)}
    if "tax_rate_pct" in i and i.get("tax_config_verified") is True:
        t = max(pbt, 0) * f(i["tax_rate_pct"]) / 100; o["tax_amount"] = q(t); o["net_profit"] = q(pbt - t)
    else: o["tax_amount"] = None; o["net_profit"] = None
    if all(k in i for k in ("change_in_receivables", "change_in_inventory", "change_in_payables")):
        o["operating_cash_estimate"] = q(pbt + dep - f(i["change_in_receivables"]) - f(i["change_in_inventory"]) + f(i["change_in_payables"]))
    else: o["operating_cash_estimate"] = None
    return o
def m04(i):
    rev = [f(x) for x in i["monthly_revenue"]]; oc = [f(x) for x in i["monthly_operating_cost"]]; n = len(rev); lag = int(i.get("collection_lag_months", 0))
    g = lambda k: [f(x) for x in i[k]] if k in i else [F(0)] * n
    cap, pr, it, fi = g("monthly_capex"), g("monthly_loan_principal"), g("monthly_loan_interest"), g("monthly_financing_inflow")
    buf = f(i.get("minimum_cash_buffer", 0)); cash = f(i["opening_cash"]); mn = cash; fneg = None; below = 0; pw = 0
    for m in range(n):
        rec = rev[m - lag] if m - lag >= 0 else F(0); net = rec + fi[m] - (oc[m] + cap[m] + pr[m] + it[m]); cash += net; profit = rev[m] - oc[m] - it[m]
        mn = min(mn, cash)
        if cash < 0 and fneg is None: fneg = m + 1
        if cash < buf: below += 1
        if profit > 0 and net < 0: pw += 1
    return {"closing_cash": q(cash), "minimum_closing_cash": q(mn), "first_month_below_zero": None if fneg is None else str(fneg), "months_below_buffer": str(below), "profitable_months_with_negative_cash": str(pw), "receivables_outstanding_end": q(sum(rev[max(0, n - lag):n]))}
def m05(i):
    d = f(i["daily_demand"]); rop = d * int(i["lead_time_days"]) + f(i["safety_stock_qty"]); o = {"reorder_point": q(rop, 4)}
    if "on_hand_qty" in i and d > 0: o["days_of_cover"] = q(f(i["on_hand_qty"]) / d, 4)
    if "unit_cost" in i and "annual_carrying_rate_pct" in i:
        h = f(i["unit_cost"]) * f(i["annual_carrying_rate_pct"]) / 100; o["annual_carrying_cost_of_safety_stock"] = q(f(i["safety_stock_qty"]) * h)
        if "order_cost" in i and "annual_demand" in i and h > 0: o["economic_order_qty"] = sqrtq(2 * f(i["annual_demand"]) * f(i["order_cost"]) / h, 4)
    return o
def m06(i):
    req = f(i["required_qty"]); rows = []; coc = f(i.get("cost_of_capital_pct", 0)) / 100
    for of in i["offers"]:
        packs = ceil(conv(req, i["base_unit"], of["pack_unit"]) / f(of["pack_size"])); goods = packs * f(of["price_per_pack"]); bought = conv(packs * f(of["pack_size"]), of["pack_unit"], i["base_unit"])
        if "min_discount_qty" in of and f(of.get("discount_pct", 0)) > 0 and bought >= f(of["min_discount_qty"]): goods *= 1 - f(of["discount_pct"]) / 100
        transport = f(of.get("transport_total", 0)); landed = goods + transport; eff = landed
        ed = f(of.get("early_pay_discount_pct", 0)) / 100; pd = int(of.get("payment_days", 0)); ep = int(of.get("early_pay_days", 0))
        if ed > 0 and pd > ep:
            ann = ed / (1 - ed) * 365 / (pd - ep)
            if ann > coc: eff = goods * (1 - ed) + transport
        rows.append((of["name"], eff, landed, packs))
    best = min(rows, key=lambda r: r[1]); o = {"best_offer": best[0]}
    for k, r in enumerate(rows): o[f"offers[{k}].effective_total"] = q(r[1]); o[f"offers[{k}].landed_total"] = q(r[2]); o[f"offers[{k}].packs"] = q(r[3], 0)
    return o
def m07(i):
    ing = sum(conv(g["qty"], g["qty_unit"], g["price_unit"]) / (1 - f(g.get("waste_pct", 0)) / 100) * f(g["price"]) for g in i["ingredients"])
    tot = ing + f(i.get("labor_hours", 0)) * f(i.get("labor_rate_per_hour", 0)) + f(i.get("energy_cost_per_batch", 0)) + f(i.get("other_cost_per_batch", 0)); sell = f(i["batch_output_units"]) * (1 - f(i.get("spoilage_pct", 0)) / 100)
    return {"ingredient_cost_per_batch": q(ing), "total_cost_per_batch": q(tot), "sellable_units_per_batch": q(sell, 4), "cost_per_sellable_unit": q(tot / sell, 4)}
def m08(i):
    cap = None; bn = None
    for r in i["resources"]:
        if f(r["required_per_unit"]) == 0: continue
        c = f(r["available"]) / f(r["required_per_unit"])
        if cap is None or c < cap: cap, bn = c, r["name"]
    pl = f(i["planned_units"]); return {"capacity_units": None if cap is None else q(cap, 4), "bottleneck": bn, "shortfall_units": q(max(F(0), pl - cap), 4) if cap is not None else "0.0000"}
def m09(i):
    u = f(i["units_to_move"]); rows = []
    for v in i["vehicles"]:
        trips = ceil(u / f(v["capacity_units"])); tot = trips * (f(v["fixed_cost_per_trip"]) + f(v["cost_per_km"]) * f(v["distance_km"])); rows.append((v["name"], tot))
    best = min(rows, key=lambda r: r[1]); o = {"best_vehicle": best[0]}
    for k, r in enumerate(rows): o[f"options[{k}].total_cost"] = q(r[1])
    if "destinations" in i:
        for k, a in enumerate(alloc(best[1], [d["units"] for d in i["destinations"]])): o[f"allocation[{k}].allocated_cost"] = q(a)
    return o
def m10(i):
    rev, cg, ar, iv, ap, days = f(i["revenue"]), f(i["cogs"]), f(i["avg_receivables"]), f(i["avg_inventory"]), f(i["avg_payables"]), int(i.get("days_in_period", 365))
    dso, dio, dpo = ar / rev * days, iv / cg * days, ap / cg * days; nwc = ar + iv - ap
    o = {"dso": q(dso), "dio": q(dio), "dpo": q(dpo), "cash_conversion_cycle_days": q(dso + dio - dpo), "net_working_capital": q(nwc)}
    if "growth_pct" in i: o["incremental_working_capital_for_growth"] = q(nwc / rev * rev * f(i["growth_pct"]) / 100)
    return o
def m11(i):
    inv = f(i["initial_investment"]); inf = [f(x) for x in i["net_inflows"]]
    def find(a):
        cum = F(0)
        for k, x in enumerate(a):
            nx = cum + x
            if nx >= inv: return str_p(k + (inv - cum) / x if x > 0 else k + 1)
            cum = nx
        return None
    str_p = lambda x: q(x, 4)
    o = {"simple_payback_periods": find(inf), "net_gain_over_horizon": q(sum(inf) + f(i.get("residual_value", 0)) - inv)}
    if "discount_rate_per_period_pct" in i:
        b = 1 + f(i["discount_rate_per_period_pct"]) / 100; o["discounted_payback_periods"] = find([x / b ** (k + 1) for k, x in enumerate(inf)])
    return o
def m12(i):
    cfs = [f(x) for x in i["cashflows"]]; o = {}
    out = -sum(c for c in cfs if c < 0); inn = sum(c for c in cfs if c > 0); o["roi_pct"] = q((inn - out) / out * 100, 4) if out else None
    if "discount_rate_pct" in i:
        r = f(i["discount_rate_pct"]) / 100
        if i.get("discount_rate_basis") == "annual_nominal_for_monthly": r /= 12
        o["npv"] = q(npv(r, cfs))
    else: o["npv"] = None
    sg = []
    for c in cfs:
        s = 0 if c == 0 else (1 if c > 0 else -1)
        if s and (not sg or sg[-1] != s): sg.append(s)
    if len(sg) < 2: o["irr_status"] = "NO_SIGN_CHANGE"; o["irr_pct_per_period"] = None; return o
    roots = []; step = F(2, 100); prev_r = F(-9, 10); prev_v = npv(prev_r, cfs)
    for k in range(1, 297):
        r = F(-9, 10) + step * k; v = npv(r, cfs)
        if prev_v != 0 and v != 0 and (prev_v > 0) != (v > 0):
            lo, hi, flo = prev_r, r, prev_v
            for _ in range(200):
                mid = (lo + hi) / 2; fm = npv(mid, cfs)
                if fm == 0: lo = hi = mid; break
                if (fm > 0) == (flo > 0): lo, flo = mid, fm
                else: hi = mid
                if hi - lo < F(1, 10**11): break
            roots.append((lo + hi) / 2)
        elif v == 0: roots.append(r)
        prev_r, prev_v = r, v
    if not roots: o["irr_status"] = "NO_ROOT_IN_RANGE"; o["irr_pct_per_period"] = None
    elif len(roots) > 1: o["irr_status"] = "MULTIPLE_ROOTS"; o["irr_pct_per_period"] = None
    else: o["irr_status"] = "OK"; o["irr_pct_per_period"] = q(roots[0] * 100, 6)
    return o
def m13(i):
    rows = loan(i["principal"], i["annual_rate_nominal_pct"], int(i["term_months"]), i["method"]); fee = f(q(f(i["principal"]) * f(i.get("upfront_fee_pct", 0)) / 100)); ti = sum(r[0] for r in rows)
    return {"first_payment": q(rows[0][2]), "last_payment": q(rows[-1][2]), "total_interest": q(ti), "upfront_fee": q(fee), "total_cost_of_credit": q(ti + fee)}
def m14(i):
    prof = [f(x) for x in i["projected_monthly_profit"]]; n = len(prof); P = f(i["amount_raised"]); o = {}
    for k, s in enumerate(i["structures"]):
        pay = []
        if s["type"] == "profit_participation":
            pay = [f(q(p * f(s["profit_share_bps"]) / 10000)) if p > 0 else F(0) for p in prof]
            if s.get("return_principal_at_end"): pay[-1] += P
        elif s["type"] == "fixed_contractual":
            fx = f(q(P * f(s["fixed_payment_pct_of_principal_per_month"]) / 100)); pay = [fx] * n
            if s.get("return_principal_at_end"): pay[-1] += P
        elif s["type"] == "bank_debt":
            rows = loan(P, s["annual_rate_nominal_pct"], int(s["term_months"]), "amortized"); pay = [rows[m][2] if m < len(rows) else F(0) for m in range(n)]
        else:
            pay = [f(q(p * f(s["ownership_pct"]) / 100 * f(s["payout_ratio_pct"]) / 100)) if p > 0 else F(0) for p in prof]
        cash = f(i["opening_cash"]) + P; mn = cash; loss = F(0)
        for m in range(n):
            cash += prof[m] - pay[m]; mn = min(mn, cash)
            if prof[m] <= 0: loss += pay[m]
        o[f"comparison[{k}].total_paid"] = q(sum(pay)); o[f"comparison[{k}].paid_in_loss_months"] = q(loss); o[f"comparison[{k}].minimum_cash"] = q(mn); o[f"comparison[{k}].closing_cash"] = q(cash)
    return o
def m15(i):
    n = len(i["progress_pct_cumulative"]); lag = int(i.get("client_payment_lag_months", 1)); sup = int(i.get("supplier_credit_months", 0)); dl = int(i.get("delay_months", 0)); rel = int(i.get("retention_release_month", 0))
    H = min(120, max(n + dl + max(lag, sup) + 1, rel)); mat = sum(f(b["qty"]) * f(b["unit_rate"]) for b in i["boq"] if b["category"] == "material"); oth = sum(f(b["qty"]) * f(b["unit_rate"]) for b in i["boq"] if b["category"] != "material")
    boq = mat + oth; tc = boq + f(i.get("approved_variation_cost", 0)); ms = mat / boq if boq else F(0); billable = f(i["contract_value"]) + f(i.get("approved_variation_value", 0)); ret_pct = f(i.get("retention_pct", 0)) / 100
    cost = [F(0)] * (H + 1); rec = [F(0)] * (H + 1); prev = F(0); rt = F(0)
    for m in range(n):
        cur = f(i["progress_pct_cumulative"][m]); incr = (cur - prev) / 100; prev = cur; c = tc * incr; cm = c * ms; co = c - cm; cost[m + 1] += co
        if m + 1 + sup <= H: cost[m + 1 + sup] += cm
        bm = m + 1 + dl; b = billable * incr; r = b * ret_pct; rt += r
        if bm + lag <= H: rec[bm + lag] += b - r
    if 0 < rel <= H: rec[rel] += rt
    for k in range(dl): cost[min(H, n + 1 + k)] += f(i.get("delay_overhead_per_month", 0))
    cash = f(i.get("opening_cash", 0)); mn = cash
    for m in range(1, H + 1): cash += rec[m] - cost[m]; mn = min(mn, cash)
    margin = billable - tc - f(i.get("delay_overhead_per_month", 0)) * dl
    return {"boq_cost_total": q(boq), "billable_value": q(billable), "estimated_margin": q(margin), "estimated_margin_pct": q(margin / billable * 100, 4), "peak_funding_gap": q(-mn if mn < 0 else F(0))}
def m16(i):
    H = int(i.get("horizon_months", 12)); g = lambda k, d=0: f(i.get(k, d)); rm = int(i.get("ramp_months", 6)); st = g("ramp_start_pct", 50) / 100
    ramp = lambda m: F(1) if rm <= 1 else st + (1 - st) * min(m - 1, rm - 1) / (rm - 1)
    lrows = loan(i["loan_principal"], g("loan_rate_nominal_pct"), int(i.get("loan_term_months", 12)), "amortized") if g("loan_principal") > 0 else []
    cash = g("opening_cash") + g("startup_funding") + g("loan_principal") - g("refundable_deposit") - g("fitout_capex") - g("opening_inventory_investment"); inv = g("opening_inventory_investment"); mn = cash; mm = 0; fp = None; cum = F(0); refund = int(i.get("deposit_refund_month", 0))
    for m in range(1, H + 1):
        sales = f(i["avg_daily_sales_at_maturity"]) * int(i.get("trading_days_per_month", 26)) * g("sales_multiplier_pct", 100) / 100 * ramp(m); cogs = sales * f(i["cogs_pct"]) / 100; draw = min(inv, cogs); inv -= draw; cc = cogs - draw
        opex = f(i["monthly_rent"]) + f(i["staff_count"]) * f(i["monthly_cost_per_staff"]) + g("other_fixed_monthly"); op = sales - cogs - opex
        ir, lp = (lrows[m - 1][0], lrows[m - 1][2]) if m - 1 < len(lrows) else (F(0), F(0)); cum += op - ir
        cn = sales - cc - opex - lp - g("fixed_investor_payment_monthly") + (g("refundable_deposit") if refund == m else F(0)); cash += cn
        if cash < mn: mn, mm = cash, m
        if op > 0 and fp is None: fp = m
    need = g("minimum_cash_buffer") - mn
    return {"lowest_cash": q(mn), "lowest_cash_month": str(mm), "additional_funding_needed": q(need if need > 0 else F(0)), "first_profitable_month": None if fp is None else str(fp), "cumulative_net_profit": q(cum), "closing_cash": q(cash)}
def m17(i):
    rev = F(0); cm = F(0)
    for p in i["products"]:
        rev += f(p["price"]) * f(p["units"]); cm += (f(p["price"]) * (1 - f(p.get("channel_fee_pct", 0)) / 100) - f(p["variable_cost"])) * f(p["units"])
    o = {"total_revenue": q(rev), "total_contribution": q(cm), "weighted_contribution_ratio_pct": q(cm / rev * 100, 4)}
    if "fixed_costs" in i:
        o["operating_profit"] = q(cm - f(i["fixed_costs"])); ratio = cm / rev
        if ratio > 0: o["mix_break_even_revenue"] = q(f(i["fixed_costs"]) / ratio)
    return o
def m18(i):
    base = f(i["base_amount"]); tot = F(0); ex = F(0); unv = 0
    for r in i["rules"]:
        if r.get("config_verified") is not True or not r.get("source_ref"): unv += 1; continue
        if r.get("basis") == "inclusive": tot += base - base / (1 + f(r["rate_pct"]) / 100)
        else: a = base * f(r.get("rate_pct", 0)) / 100 + f(r.get("flat", 0)); tot += a; ex += a
    return {"total_verified_charges": q(tot), "unverified_rule_count": str(unv), "amount_after_exclusive_charges": q(base + ex)}
def m19(i):
    s = i["sites"]; ext = sum(f(x["revenue_external"]) for x in s); ir = sum(f(x.get("revenue_internal", 0)) for x in s); ec = sum(f(x["cost_external"]) for x in s); ic = sum(f(x.get("cost_internal", 0)) for x in s)
    return {"consolidated_revenue": q(ext), "eliminated_internal_revenue": q(ir), "elimination_difference": q(ir - ic), "consolidated_profit": q(ext - ec)}
def m20(i):
    v = {k: f(x) for k, x in i["values"].items()}; return {"results.profit": q(v["units"] * (v["price"] - v["cost"]) - v["fixed"]), "results.be": q(v["fixed"] / (v["price"] - v["cost"]))}

FIX = []
def add(id, model, inputs, version=None, adverse=False, note=""):
    FIX.append({"id": id, "model": model, "version": version, "adverse": adverse, "note": note, "inputs": inputs})
add("M01-base-v1", "M01", {"unit_cost": "60", "selling_price": "100", "discount_pct": "10", "waste_pct": "5", "units": "200"}, "1.0.0")
add("M01-loss-v1", "M01", {"unit_cost": "80", "selling_price": "100", "discount_pct": "25", "waste_pct": "10"}, "1.0.0", True, "discount pushes price below cost")
add("M01-fee-v2", "M01", {"unit_cost": "60", "selling_price": "100", "discount_pct": "10", "waste_pct": "5", "channel_fee_pct": "12", "units": "50"}, "2.0.0")
add("M01-fee-loss-v2", "M01", {"unit_cost": "75", "selling_price": "100", "channel_fee_pct": "30"}, "2.0.0", True)
add("M02-base", "M02", {"fixed_costs": "120000", "unit_price": "100", "variable_cost_per_unit": "60", "target_profit": "40000"})
add("M02-infeasible", "M02", {"fixed_costs": "120000", "unit_price": "55", "variable_cost_per_unit": "60"}, None, True)
add("M03-verified-tax", "M03", {"revenue": "500000", "cogs": "300000", "operating_expenses": "120000", "depreciation": "10000", "interest_expense": "5000", "tax_rate_pct": "20", "tax_config_verified": True, "change_in_receivables": "30000", "change_in_inventory": "10000", "change_in_payables": "15000"})
add("M03-loss-no-tax-config", "M03", {"revenue": "100000", "cogs": "80000", "operating_expenses": "40000", "interest_expense": "2000", "tax_rate_pct": "20", "tax_config_verified": False}, None, True)
add("M04-profit-negative-cash", "M04", {"opening_cash": "50000", "monthly_revenue": ["100000"] * 6, "monthly_operating_cost": ["60000"] * 6, "collection_lag_months": 2, "monthly_capex": ["80000", "0", "0", "0", "0", "0"], "monthly_loan_principal": ["0"] * 6, "monthly_loan_interest": ["0"] * 6, "minimum_cash_buffer": "20000"}, None, True)
add("M04-healthy", "M04", {"opening_cash": "200000", "monthly_revenue": ["100000", "110000", "120000"], "monthly_operating_cost": ["70000", "72000", "74000"], "monthly_financing_inflow": ["0", "50000", "0"]})
add("M05-base", "M05", {"daily_demand": "20", "lead_time_days": 7, "safety_stock_qty": "30", "on_hand_qty": "100", "unit_cost": "50", "annual_carrying_rate_pct": "20", "order_cost": "200", "annual_demand": "7300"})
add("M05-stockout", "M05", {"daily_demand": "35.5", "lead_time_days": 14, "safety_stock_qty": "0", "on_hand_qty": "120"}, None, True)
add("M06-early-discount", "M06", {"required_qty": "100", "base_unit": "kg", "cost_of_capital_pct": "10", "offers": [{"name": "A", "price_per_pack": "4800", "pack_size": "50", "pack_unit": "kg", "transport_total": "300", "payment_days": 30, "early_pay_discount_pct": "2", "early_pay_days": 10}, {"name": "B", "price_per_pack": "110", "pack_size": "1", "pack_unit": "kg"}]})
add("M06-overbuy-volume", "M06", {"required_qty": "120", "base_unit": "kg", "offers": [{"name": "Drum", "price_per_pack": "9000", "pack_size": "100", "pack_unit": "kg", "min_discount_qty": "200", "discount_pct": "5"}, {"name": "Bag", "price_per_pack": "2400", "pack_size": "25", "pack_unit": "kg", "transport_total": "500"}]}, None, True, "pack granularity causes overbuy; discount not reached")
add("M07-sweet-batch", "M07", {"ingredients": [{"name": "milk", "qty": "20", "qty_unit": "l", "price": "90", "price_unit": "l", "waste_pct": "2"}, {"name": "sugar", "qty": "5000", "qty_unit": "g", "price": "120", "price_unit": "kg"}], "batch_output_units": "200", "spoilage_pct": "4", "labor_hours": "6", "labor_rate_per_hour": "150", "energy_cost_per_batch": "450", "other_cost_per_batch": "100"})
add("M07-high-spoilage", "M07", {"ingredients": [{"name": "flour", "qty": "10", "qty_unit": "kg", "price": "60", "price_unit": "kg"}], "batch_output_units": "100", "spoilage_pct": "40"}, None, True)
add("M08-bottleneck", "M08", {"planned_units": "700", "resources": [{"name": "oven_hours", "available": "40", "required_per_unit": "0.05"}, {"name": "packing_staff_hours", "available": "120", "required_per_unit": "0.2"}]}, None, True)
add("M08-ok", "M08", {"planned_units": "100", "resources": [{"name": "machine", "available": "200", "required_per_unit": "0.5"}, {"name": "idle", "available": "5", "required_per_unit": "0"}]})
add("M09-van-vs-truck", "M09", {"units_to_move": "900", "vehicles": [{"name": "van", "fixed_cost_per_trip": "500", "cost_per_km": "20", "distance_km": "30", "capacity_units": "300"}, {"name": "truck", "fixed_cost_per_trip": "1500", "cost_per_km": "40", "distance_km": "30", "capacity_units": "1000"}], "destinations": [{"site": "A", "units": "500"}, {"site": "B", "units": "250"}, {"site": "C", "units": "150"}]})
add("M09-rounding-alloc", "M09", {"units_to_move": "3", "vehicles": [{"name": "v", "fixed_cost_per_trip": "100", "cost_per_km": "0", "distance_km": "0", "capacity_units": "10"}], "destinations": [{"site": "A", "units": "1"}, {"site": "B", "units": "1"}, {"site": "C", "units": "1"}]}, None, True, "100.00 over 3 sites must still add to 100.00")
add("M10-growth", "M10", {"revenue": "1200000", "cogs": "800000", "avg_receivables": "150000", "avg_inventory": "100000", "avg_payables": "60000", "days_in_period": 90, "growth_pct": "30"})
add("M10-long-credit", "M10", {"revenue": "600000", "cogs": "540000", "avg_receivables": "300000", "avg_inventory": "270000", "avg_payables": "30000"}, None, True)
add("M11-payback", "M11", {"initial_investment": "800000", "nonrecoverable_setup": "100000", "net_inflows": ["25000"] * 40, "discount_rate_per_period_pct": "1", "residual_value": "50000"})
add("M11-never", "M11", {"initial_investment": "800000", "net_inflows": ["10000"] * 12}, None, True)
add("M12-single-root", "M12", {"cashflows": ["-1000", "400", "400", "400"], "period": "year", "discount_rate_pct": "10"})
add("M12-multiple-roots", "M12", {"cashflows": ["-100", "230", "-132"], "period": "year", "discount_rate_pct": "10"}, None, True)
add("M12-no-sign-change", "M12", {"cashflows": ["-100", "-50"], "period": "month"}, None, True)
add("M12-monthly-nominal", "M12", {"cashflows": ["-12000", "1100", "1100", "1100", "1100", "1100", "1100", "1100", "1100", "1100", "1100", "1100", "1100"], "period": "month", "discount_rate_pct": "12", "discount_rate_basis": "annual_nominal_for_monthly"})
add("M13-amortized", "M13", {"principal": "500000", "annual_rate_nominal_pct": "12", "term_months": 12, "method": "amortized", "upfront_fee_pct": "1"})
add("M13-fixed-principal", "M13", {"principal": "100000", "annual_rate_nominal_pct": "18", "term_months": 7, "method": "fixed_principal"})
add("M13-bullet-zero-rate", "M13", {"principal": "250000", "annual_rate_nominal_pct": "0", "term_months": 5, "method": "bullet"}, None, True)
add("M14-four-structures", "M14", {"amount_raised": "1000000", "opening_cash": "100000", "projected_monthly_profit": ["-20000", "30000", "60000", "90000", "-10000", "50000"], "minimum_cash_buffer": "0", "structures": [{"name": "PP14", "type": "profit_participation", "profit_share_bps": "1400"}, {"name": "Fixed", "type": "fixed_contractual", "fixed_payment_pct_of_principal_per_month": "1.5", "return_principal_at_end": True}, {"name": "Bank", "type": "bank_debt", "annual_rate_nominal_pct": "14", "term_months": 12}, {"name": "Eq", "type": "equity", "ownership_pct": "20", "payout_ratio_pct": "50"}]})
add("M14-loss-stress", "M14", {"amount_raised": "500000", "opening_cash": "20000", "projected_monthly_profit": ["-40000", "-30000", "-20000", "10000"], "minimum_cash_buffer": "0", "structures": [{"name": "PP", "type": "profit_participation", "profit_share_bps": "1400"}, {"name": "Fixed", "type": "fixed_contractual", "fixed_payment_pct_of_principal_per_month": "2"}]}, None, True)
add("M15-delay", "M15", {"contract_value": "10000000", "boq": [{"item": "cement", "category": "material", "qty": "1000", "unit_rate": "6000"}, {"item": "labor", "category": "labor", "qty": "1", "unit_rate": "2000000"}], "progress_pct_cumulative": ["25", "50", "75", "100"], "retention_pct": "5", "retention_release_month": 9, "client_payment_lag_months": 1, "supplier_credit_months": 0, "delay_months": 2, "delay_overhead_per_month": "100000", "approved_variation_value": "500000", "approved_variation_cost": "300000", "unapproved_variation_value": "200000"}, None, True)
add("M15-supplier-credit", "M15", {"contract_value": "4000000", "boq": [{"item": "steel", "category": "material", "qty": "100", "unit_rate": "20000"}, {"item": "crew", "category": "labor", "qty": "1", "unit_rate": "1000000"}], "progress_pct_cumulative": ["50", "100"], "retention_pct": "10", "retention_release_month": 6, "client_payment_lag_months": 2, "supplier_credit_months": 2, "opening_cash": "100000"})
add("M16-branch-infeasible", "M16", {"monthly_rent": "60000", "staff_count": "8", "monthly_cost_per_staff": "18000", "avg_daily_sales_at_maturity": "40000", "cogs_pct": "55", "fitout_capex": "900000", "refundable_deposit": "360000", "opening_inventory_investment": "150000", "startup_funding": "1400000"}, None, True, "setup outflows exceed funding")
add("M16-branch-funded-loan", "M16", {"monthly_rent": "60000", "staff_count": "8", "monthly_cost_per_staff": "18000", "avg_daily_sales_at_maturity": "40000", "cogs_pct": "55", "fitout_capex": "900000", "refundable_deposit": "360000", "deposit_refund_month": 12, "opening_inventory_investment": "150000", "startup_funding": "1000000", "loan_principal": "600000", "loan_rate_nominal_pct": "13", "loan_term_months": 24, "fixed_investor_payment_monthly": "8000", "sales_multiplier_pct": "80", "minimum_cash_buffer": "100000"})
add("M16-slow-ramp", "M16", {"horizon_months": 12, "monthly_rent": "30000", "staff_count": "3", "monthly_cost_per_staff": "15000", "avg_daily_sales_at_maturity": "9000", "cogs_pct": "62", "ramp_months": 9, "ramp_start_pct": "30", "startup_funding": "500000", "fitout_capex": "200000"}, None, True)
add("M17-mix", "M17", {"products": [{"name": "cake", "price": "800", "variable_cost": "500", "units": "300", "channel_fee_pct": "10"}, {"name": "snack", "price": "50", "variable_cost": "40", "units": "5000"}, {"name": "drink", "price": "30", "variable_cost": "12", "units": "2000"}], "fixed_costs": "150000"})
add("M17-negative-mix", "M17", {"products": [{"name": "loss_leader", "price": "100", "variable_cost": "110", "units": "1000"}, {"name": "ok", "price": "100", "variable_cost": "70", "units": "100"}], "fixed_costs": "1000"}, None, True)
add("M18-verified-and-not", "M18", {"base_amount": "1000", "rules": [{"name": "fee", "kind": "fee", "rate_pct": "1.5", "flat": "2", "basis": "exclusive", "config_verified": True, "source_ref": "owner doc 1"}, {"name": "levy-incl", "kind": "tax", "rate_pct": "5", "basis": "inclusive", "config_verified": True, "source_ref": "owner doc 2"}, {"name": "no-source", "kind": "tax", "rate_pct": "15", "basis": "exclusive", "config_verified": True}]}, None, True)
add("M18-all-verified", "M18", {"base_amount": "250.50", "rules": [{"name": "fee", "kind": "fee", "rate_pct": "2", "basis": "exclusive", "config_verified": True, "source_ref": "bank letter"}]})
add("M19-balanced", "M19", {"sites": [{"site_id": "F", "tenant_id": "T1", "business_id": "B", "revenue_external": "0", "revenue_internal": "100000", "cost_external": "70000"}, {"site_id": "S", "tenant_id": "T1", "business_id": "B", "revenue_external": "130000", "cost_external": "20000", "cost_internal": "100000"}]})
add("M19-mismatch", "M19", {"sites": [{"site_id": "F", "tenant_id": "T1", "business_id": "B", "revenue_external": "5000", "revenue_internal": "100000", "cost_external": "70000"}, {"site_id": "S", "tenant_id": "T1", "business_id": "B", "revenue_external": "130000", "cost_external": "20000", "cost_internal": "90000"}]}, None, True)
add("M20-template", "M20", {"template": {"inputs": ["units", "price", "cost", "fixed"], "outputs": [{"k": "profit", "expr": "units*(price-cost)-fixed"}, {"k": "be", "expr": "fixed/(price-cost)"}]}, "values": {"units": "1000", "price": "100", "cost": "60", "fixed": "20000"}})
add("M20-negative-profit", "M20", {"template": {"inputs": ["units", "price", "cost", "fixed"], "outputs": [{"k": "profit", "expr": "units*(price-cost)-fixed"}, {"k": "be", "expr": "fixed/(price-cost)"}]}, "values": {"units": "100", "price": "100", "cost": "60", "fixed": "20000"}}, None, True)

def expect(fx):
    m, i = fx["model"], fx["inputs"]
    if m == "M01": return m01(i, fx["version"] == "2.0.0")
    return globals()[m.lower()](i)
def build():
    out = []
    for fx in FIX:
        e = {k: v for k, v in expect(fx).items()}; c = dict(fx); c["expect"] = e; out.append(c)
    return out
if __name__ == "__main__":
    path = __file__.rsplit("/", 1)[0] + "/golden.json"; text = json.dumps(build(), indent=1, ensure_ascii=False, sort_keys=True) + "\n"
    if "--check" in sys.argv:
        cur = open(path).read()
        if cur != text: print("golden.json DRIFT: engine fixtures differ from independent reference"); sys.exit(1)
        print("golden.json matches independent python reference (%d fixtures)" % len(FIX))
    else: open(path, "w").write(text); print("wrote", path, len(FIX))
