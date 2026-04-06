---
name: opentaxsolver
description: Prepare and compute tax forms using OpenTaxSolver (OTS) v23.06 for Tax Year 2025. Create and edit input files, run solvers, and generate filled PDF forms. Supports US 1040, Schedule C, Schedule SE, MI-1040, and other forms. Use when asked to prepare taxes, fill out tax forms, run tax calculations, or generate tax PDFs with OpenTaxSolver.
---

# OpenTaxSolver (OTS)

Installed at: `~/.local/share/OpenTaxSolver/`
Version: v23.06 (Tax Year 2025)

## How OTS Works

1. **Create an input file** from a template (plain text with line entries)
2. **Run the solver** to compute tax amounts
3. **Output** goes to a `_out.txt` file with computed results
4. Optionally **generate a filled PDF** using `universal_pdf_file_modifier`

## Directory Layout

```
~/.local/share/OpenTaxSolver/
  bin/                      # Solver binaries
  tax_form_files/           # Templates and examples per form
    US_1040/                # Federal 1040
    US_1040_Sched_C/        # Schedule C (Business income)
    US_1040_Sched_SE/       # Schedule SE (Self-employment tax)
    MI_1040/                # Michigan state
    ... (AZ, CA, MA, NC, NJ, NY, OH, OR, PA, VA, Form_*)
```

## Available Solvers

| Form | Binary | Template |
|---|---|---|
| US 1040 | `bin/taxsolve_US_1040_2025` | `tax_form_files/US_1040/US_1040_template.txt` |
| Schedule C | `bin/taxsolve_US_1040_Sched_C_2025` | `tax_form_files/US_1040_Sched_C/US_1040Sched_C_2025_template.txt` |
| Schedule SE | `bin/taxsolve_US_1040_Sched_SE_2025` | `tax_form_files/US_1040_Sched_SE/US_1040_Sched_SE_template.txt` |
| MI 1040 | `bin/taxsolve_MI_1040_2025` | `tax_form_files/MI_1040/MI_1040_2024_template.txt` |
| Form 8829 | `bin/taxsolve_f8829_2025` | `tax_form_files/Form_8829/` |
| Form 8889 (HSA) | `bin/taxsolve_HSA_f8889` | `tax_form_files/HSA_Form_8889/` |
| Form 8995 (QBI) | `bin/taxsolve_f8995_2025` | `tax_form_files/Form_8995/` |
| Form 2210 | `bin/taxsolve_f2210_2025` | `tax_form_files/Form_2210/` |

## Workflow

### 1. Create Input File

Copy a template and fill in values. The format uses line labels followed by values:

```
Status    Single    { Single, Married/Joint, Head_of_House, Married/Sep, Widow(er) }

L1a   50000.00     { Wages }
      ;

L2b   1200.00      { Taxable Interest }
      ;
```

- Values go after the line label
- Multiple entries for the same line end with `;`
- Comments are in `{ curly braces }`
- Leave lines blank or at 0 if not applicable

### 2. Run the Solver

```bash
OTS=~/.local/share/OpenTaxSolver

# Run a solver on an input file
$OTS/bin/taxsolve_US_1040_2025 my_fed1040_2025.txt

# Output is written to my_fed1040_2025_out.txt
```

The solver reads the input file and writes a `_out.txt` file with all computed values.

### 3. Generate Filled PDF (optional)

```bash
$OTS/bin/universal_pdf_file_modifier my_fed1040_2025_out.txt
```

This fills in a PDF version of the tax form using the computed output.

## Input File Format Details

### Federal 1040 Key Lines

- **Status**: `Single`, `Married/Joint`, `Head_of_House`, `Married/Sep`, `Widow(er)`
- **L1a**: Wages (W-2 box 1) — multiple entries end with `;`
- **L2a/L2b**: Tax-exempt / Taxable interest
- **L3a/L3b**: Qualified / Ordinary dividends
- **L4a/L4b**: IRA distributions (total / taxable)
- **L6a**: Social Security benefits
- **L25a/L25b/L25c**: Federal tax withheld (W-2 / 1099 / other)
- **L26**: Estimated tax payments
- **S1_3**: Business income from Schedule C
- **S1_15**: Deductible part of self-employment tax (from Schedule SE)
- **S1_16**: Self-employed SEP/SIMPLE/qualified plans
- **S1_17**: Self-employed health insurance deduction
- **S2_4**: Self-employment tax (from Schedule SE)
- **CapGains-A/D through CapGains-I/L**: Capital gains entries
- **A1-A18**: Schedule A itemized deductions
- **Personal info**: `Your1stName`, `YourLastName`, `YourSocSec#`, address fields

### Schedule C Key Lines

- **L1**: Gross receipts — multiple entries end with `;`
- **L8-L27a**: Expense categories (advertising, car, contract labor, insurance, office, rent, supplies, taxes, travel, meals, utilities, wages, etc.)
- **L30**: Business use of home (Form 8829)
- **L44a-L44c**: Vehicle miles (business, commuting, other)
- **L48a-L48i**: Other expenses (description + amount pairs)

### Schedule SE Key Lines

- **L2**: Net profit/loss from Schedule C line 31
- **L5a**: Church employee income
- **L8a**: Total social security wages and tips

### MI 1040 Key Lines

- **Status**: `Single`, `Married/Joint`, `Married/Sep`
- **L9a-L9e**: Exemptions
- **L10**: AGI from federal 1040
- **L13**: Subtractions from MI Schedule 1
- **L26**: Property Tax Credit
- **L31**: Michigan tax withheld (Schedule W)
- **L32**: Estimated tax payments

## Order of Operations

For self-employed filing federal + Michigan:

1. **Schedule C** first — produces net business income (line 31)
2. **Schedule SE** — uses Schedule C line 31 to compute SE tax
3. **US 1040** — imports Schedule C income (S1_3) and SE tax (S2_4, S1_15)
4. **MI 1040** — uses federal AGI (L10) from US 1040

## Tips

- Keep input files in a working directory outside the OTS install (e.g., in the Taxes 2025 project folder)
- Each template has a corresponding `_example.txt` and `README_*.txt` for reference
- The `Round_PDF_to_Whole_Dollars` option at the bottom of templates controls PDF formatting
- Output files include detailed line-by-line calculations and marginal tax bracket info
- You can reference a prior year's output file for carryover values (e.g., Schedule D line D6)
