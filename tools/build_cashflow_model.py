import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from openpyxl.utils import get_column_letter
from datetime import date

wb = openpyxl.Workbook()

# Color palette
NAVY = "1B365D"
SLATE = "2C5282"
LIGHT_BG = "F0F4F8"
ACCENT_BG = "E6FFFA"
WARN_BG = "FFF5F5"
WHITE = "FFFFFF"
BORDER_GRAY = "CBD5E0"

thin = Side(border_style="thin", color=BORDER_GRAY)
grid_border = Border(left=thin, right=thin, top=thin, bottom=thin)

hdr_font = Font(name="Calibri", size=11, bold=True, color=WHITE)
sec_font = Font(name="Calibri", size=11, bold=True, color=NAVY)
body_font = Font(name="Calibri", size=10, color="1A202C")
input_font = Font(name="Calibri", size=10, bold=True, color="0B5394")
bold_font = Font(name="Calibri", size=10, bold=True, color="1A202C")

hdr_fill = PatternFill("solid", fgColor=NAVY)
subhdr_fill = PatternFill("solid", fgColor=SLATE)
zebra_fill = PatternFill("solid", fgColor=LIGHT_BG)
input_fill = PatternFill("solid", fgColor=ACCENT_BG)

INR_FMT = '₹#,##0;-"₹"#,##0;"₹"0'
PCT_FMT = "0.0%"

# ---------------------------------------------------------
# SHEET 1: Admin_Scenarios (Inputs & What-If Drivers)
# ---------------------------------------------------------
ws_adm = wb.active
ws_adm.title = "Admin_Scenarios"
ws_adm.views.sheetView[0].showGridLines = True

ws_adm["A1"] = "SDE 24-MONTH CASH FLOW & WHAT-IF FORECAST MODEL"
ws_adm["A1"].font = Font(name="Calibri", size=14, bold=True, color=NAVY)
ws_adm["A2"] = "Edit green-shaded cells. Select Active Scenario in C4 to switch live 24-month projections."
ws_adm["A2"].font = Font(name="Calibri", size=9, italic=True, color="4A5568")

ws_adm["A4"] = "Active Scenario (1=Base, 2=Best, 3=Worst, 4=Stress)"
ws_adm["A4"].font = bold_font
ws_adm["C4"] = 1
ws_adm["C4"].font = input_font
ws_adm["C4"].fill = input_fill
ws_adm["C4"].alignment = Alignment(horizontal="center")

ws_adm["A5"] = "Opening Bank Cash Balance (INR)"
ws_adm["A5"].font = bold_font
ws_adm["C5"] = 4500000
ws_adm["C5"].font = input_font
ws_adm["C5"].fill = input_fill
ws_adm["C5"].number_format = INR_FMT

ws_adm["A6"] = "Minimum Safety Cash Cushion (INR)"
ws_adm["A6"].font = bold_font
ws_adm["C6"] = 1000000
ws_adm["C6"].font = input_font
ws_adm["C6"].fill = input_fill
ws_adm["C6"].number_format = INR_FMT

# Scenario Driver Matrix
headers_sc = [
    "Driver / Assumption",
    "1: Base Case",
    "2: Best Case",
    "3: Worst Case",
    "4: Stress (Hires + Slippage)",
    "Active Value",
]
for col_idx, text in enumerate(headers_sc, start=1):
    c = ws_adm.cell(row=8, column=col_idx, value=text)
    c.font = hdr_font
    c.fill = hdr_fill
    c.alignment = Alignment(horizontal="center", vertical="center", wrap_text=True)
    c.border = grid_border

drivers = [
    ("Base Monthly Interest & Fee Inflow (INR)", 1850000, 2150000, 1500000, 1650000, INR_FMT),
    ("Monthly Portfolio Inflow Growth Rate", 0.015, 0.025, 0.005, 0.010, PCT_FMT),
    ("Collection Efficiency / Realization Rate", 0.94, 0.98, 0.85, 0.88, PCT_FMT),
    ("Base Monthly Fixed OpEx & Branch Rent (INR)", 720000, 720000, 750000, 750000, INR_FMT),
    ("Variable Incentive & Conveyance (% of Inflow)", 0.06, 0.065, 0.05, 0.07, PCT_FMT),
    ("New Field/Ops Hires Added (Headcount)", 0, 2, 0, 3, "#,##0"),
    ("Monthly Cost per New Hire (INR)", 38000, 38000, 38000, 40000, INR_FMT),
    ("New Hires Start Month (1 to 24)", 4, 4, 6, 3, "#,##0"),
    ("Optional Capital / Credit Line Infusion in Month 3 (INR)", 0, 0, 1000000, 1500000, INR_FMT),
]

for idx, (label, v1, v2, v3, v4, fmt) in enumerate(drivers, start=9):
    ws_adm.cell(row=idx, column=1, value=label).font = body_font
    ws_adm.cell(row=idx, column=1).border = grid_border
    for c_i, val in enumerate([v1, v2, v3, v4], start=2):
        cell = ws_adm.cell(row=idx, column=c_i, value=val)
        cell.font = input_font
        cell.fill = input_fill
        cell.number_format = fmt
        cell.border = grid_border
    act = ws_adm.cell(row=idx, column=6, value=f"=INDEX(B{idx}:E{idx},1,$C$4)")
    act.font = bold_font
    act.number_format = fmt
    act.border = grid_border

# Seasonality Table (Months 1-12)
ws_adm["A20"] = "Seasonality Multipliers (Calendar Month 1 = Jan .. 12 = Dec)"
ws_adm["A20"].font = sec_font
season_vals = [0.95, 0.98, 1.12, 0.92, 0.95, 1.00, 1.00, 1.02, 1.05, 1.08, 1.00, 1.05]
for m in range(1, 13):
    h = ws_adm.cell(row=21, column=m, value=f"M{m}")
    h.font = hdr_font
    h.fill = subhdr_fill
    h.alignment = Alignment(horizontal="center")
    h.border = grid_border
    v = ws_adm.cell(row=22, column=m, value=season_vals[m - 1])
    v.font = input_font
    v.fill = input_fill
    v.number_format = "0.00"
    v.alignment = Alignment(horizontal="center")
    v.border = grid_border

# ---------------------------------------------------------
# SHEET 2: Forecast_24M (Executive KPIs + 24-Month Projection)
# ---------------------------------------------------------
ws_fc = wb.create_sheet("Forecast_24M")
ws_fc.views.sheetView[0].showGridLines = True

ws_fc["A1"] = "24-MONTH ROLLING CASH FLOW & RUNWAY FORECAST"
ws_fc["A1"].font = Font(name="Calibri", size=14, bold=True, color=NAVY)
ws_fc["A2"] = "=CHOOSE(Admin_Scenarios!C4,\"Scenario 1: Base Case\",\"Scenario 2: Best Case\",\"Scenario 3: Worst Case\",\"Scenario 4: Stress (Hires + Slippage)\")"
ws_fc["A2"].font = Font(name="Calibri", size=11, bold=True, color="0B5394")

# Top KPI Summary Strip
kpis = [
    ("A4", "24M Total Net Inflow", "A5", "=SUM(B10:Y10)", INR_FMT),
    ("D4", "24M Total Outflow", "D5", "=SUM(B14:Y14)", INR_FMT),
    ("G4", "24M Net Cash Surplus / (Deficit)", "G5", "=SUM(B15:Y15)", INR_FMT),
    ("J4", "Lowest Cash Balance (24M)", "J5", "=MIN(B17:Y17)", INR_FMT),
    ("M4", "Ending Cash (Month 24)", "M5", "=Y17", INR_FMT),
    ("P4", "Months Below Safety Cushion", "P5", "=COUNTIF(B17:Y17,\"<\"&Admin_Scenarios!C6)", "#,##0"),
]
for lbl_cell, lbl_text, val_cell, formula, fmt in kpis:
    ws_fc[lbl_cell] = lbl_text
    ws_fc[lbl_cell].font = Font(name="Calibri", size=9, bold=True, color="4A5568")
    ws_fc[val_cell] = formula
    ws_fc[val_cell].font = Font(name="Calibri", size=12, bold=True, color=NAVY)
    ws_fc[val_cell].number_format = fmt

# Table Header Row 8
ws_fc["A8"] = "Line Item (INR)"
ws_fc["A8"].font = hdr_font
ws_fc["A8"].fill = hdr_fill
ws_fc["A8"].border = grid_border

start_year, start_month = 2026, 12
for m_idx in range(1, 25):
    col = m_idx + 1
    col_ltr = get_column_letter(col)
    yr = start_year + ((start_month - 1 + (m_idx - 1)) // 12)
    mo = ((start_month - 1 + (m_idx - 1)) % 12) + 1
    c = ws_fc.cell(row=8, column=col, value=date(yr, mo, 1))
    c.font = hdr_font
    c.fill = hdr_fill
    c.number_format = "mmm-yy"
    c.alignment = Alignment(horizontal="center")
    c.border = grid_border

row_labels = {
    9: ("Gross Scheduled Inflow", body_font, None, INR_FMT),
    10: ("Net Realized Cash Inflow (Post Collection %)", bold_font, zebra_fill, INR_FMT),
    11: ("Fixed OpEx & Branch Overhead", body_font, None, INR_FMT),
    12: ("Variable Incentives & Conveyance", body_font, None, INR_FMT),
    13: ("New Hires Payroll Cost", body_font, None, INR_FMT),
    14: ("Total Operating Outflow", bold_font, zebra_fill, INR_FMT),
    15: ("Net Operating Cash Flow", bold_font, None, INR_FMT),
    16: ("Capital / Credit Line Infusion", body_font, None, INR_FMT),
    17: ("Ending Bank Cash Balance", bold_font, input_fill, INR_FMT),
    18: ("Cushion Variance vs Safety Target", body_font, None, INR_FMT),
}

for r, (text, fnt, fill, fmt) in row_labels.items():
    cell = ws_fc.cell(row=r, column=1, value=text)
    cell.font = fnt
    if fill:
        cell.fill = fill
    cell.border = grid_border

for m_idx in range(1, 25):
    col = m_idx + 1
    c_ltr = get_column_letter(col)
    prev_ltr = get_column_letter(col - 1)

    # Gross scheduled inflow with growth & calendar-month seasonality
    f_gross = (
        f"=Admin_Scenarios!$F$9*((1+Admin_Scenarios!$F$10)^({m_idx}-1))"
        f"*INDEX(Admin_Scenarios!$A$22:$L$22,1,MONTH({c_ltr}$8))"
    )
    f_net_in = f"={c_ltr}9*Admin_Scenarios!$F$11"
    f_fixed = "=Admin_Scenarios!$F$12"
    f_var = f"={c_ltr}10*Admin_Scenarios!$F$13"
    f_hires = f"=IF({m_idx}>=Admin_Scenarios!$F$16,Admin_Scenarios!$F$14*Admin_Scenarios!$F$15,0)"
    f_tot_out = f"=SUM({c_ltr}11:{c_ltr}13)"
    f_net_cf = f"={c_ltr}10-{c_ltr}14"
    f_infusion = f"=IF({m_idx}=3,Admin_Scenarios!$F$17,0)"
    f_end_cash = (
        f"=Admin_Scenarios!$C$5+{c_ltr}15+{c_ltr}16"
        if m_idx == 1
        else f"={prev_ltr}17+{c_ltr}15+{c_ltr}16"
    )
    f_cushion = f"={c_ltr}17-Admin_Scenarios!$C$6"

    formulas = {
        9: f_gross,
        10: f_net_in,
        11: f_fixed,
        12: f_var,
        13: f_hires,
        14: f_tot_out,
        15: f_net_cf,
        16: f_infusion,
        17: f_end_cash,
        18: f_cushion,
    }
    for r, form in formulas.items():
        _, fnt, fill, fmt = row_labels[r]
        cell = ws_fc.cell(row=r, column=col, value=form)
        cell.font = fnt
        if fill:
            cell.fill = fill
        cell.number_format = fmt
        cell.border = grid_border

# ---------------------------------------------------------
# SHEET 3: Budget_vs_Actuals (Monthly Variance Tracker)
# ---------------------------------------------------------
ws_bva = wb.create_sheet("Budget_vs_Actuals")
ws_bva.views.sheetView[0].showGridLines = True

ws_bva["A1"] = "BUDGET VS. ACTUALS — MONTHLY VARIANCE TRACKER"
ws_bva["A1"].font = Font(name="Calibri", size=14, bold=True, color=NAVY)

bva_headers = ["Category", "Budgeted (INR)", "Actual (INR)", "Variance (INR)", "Variance %", "Status"]
for c_i, h_text in enumerate(bva_headers, start=1):
    c = ws_bva.cell(row=3, column=c_i, value=h_text)
    c.font = hdr_font
    c.fill = hdr_fill
    c.alignment = Alignment(horizontal="center")
    c.border = grid_border

bva_rows = [
    ("Interest & EMI Collection Inflow", 1739000, 1695000),
    ("Processing Fee & Penal Inflow", 145000, 162000),
    ("Branch Rent & Fixed Admin", 420000, 420000),
    ("Staff Payroll & Field Conveyance", 410000, 428000),
    ("Legal, CIBIL & Verification Costs", 65000, 58000),
]
for idx, (cat, bud, act) in enumerate(bva_rows, start=4):
    ws_bva.cell(row=idx, column=1, value=cat).font = body_font
    ws_bva.cell(row=idx, column=1).border = grid_border

    c_b = ws_bva.cell(row=idx, column=2, value=bud)
    c_b.font = input_font
    c_b.fill = input_fill
    c_b.number_format = INR_FMT
    c_b.border = grid_border

    c_a = ws_bva.cell(row=idx, column=3, value=act)
    c_a.font = input_font
    c_a.fill = input_fill
    c_a.number_format = INR_FMT
    c_a.border = grid_border

    c_v = ws_bva.cell(row=idx, column=4, value=f"=C{idx}-B{idx}")
    c_v.font = bold_font
    c_v.number_format = INR_FMT
    c_v.border = grid_border

    c_p = ws_bva.cell(row=idx, column=5, value=f"=IF(B{idx}=0,0,D{idx}/B{idx})")
    c_p.font = body_font
    c_p.number_format = PCT_FMT
    c_p.border = grid_border

    c_s = ws_bva.cell(row=idx, column=6, value=f"=IF(ABS(E{idx})<=0.05,\"On Track\",IF(D{idx}>0,\"Above Plan\",\"Review Variance\"))")
    c_s.font = bold_font
    c_s.alignment = Alignment(horizontal="center")
    c_s.border = grid_border

# Auto-fit column widths cleanly
for ws in [ws_adm, ws_fc, ws_bva]:
    for col in ws.columns:
        max_len = 0
        col_ltr = get_column_letter(col[0].column)
        for cell in col:
            val_str = str(cell.value or "")
            if not val_str.startswith("="):
                max_len = max(max_len, len(val_str))
        ws.column_dimensions[col_ltr].width = max(max_len + 4, 15)

ws_fc.column_dimensions["A"].width = 42
ws_adm.column_dimensions["A"].width = 48
ws_bva.column_dimensions["A"].width = 36

out_file = "tools/SDE_24M_CashFlow_WhatIf_Forecast.xlsx"
wb.save(out_file)
print(f"Created {out_file} successfully.")
