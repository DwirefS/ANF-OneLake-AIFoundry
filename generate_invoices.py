import os
import random
from datetime import datetime, timedelta

# Ensure directory exists
os.makedirs('test_data/invoices', exist_ok=True)

vendors = [
    {"name": "Azure Cloud Services", "address": "1 Microsoft Way, Redmond, WA"},
    {"name": "OfficeMax", "address": "222 Merchandise Mart Pl, Chicago, IL"},
    {"name": "WeWork", "address": "575 Lexington Ave, New York, NY"},
    {"name": "Dell Computers", "address": "1 Dell Way, Round Rock, TX"},
    {"name": "Staffing Agency", "address": "123 Recruiters Ln, Austin, TX"},
]

def generate_invoice(invoice_id):
    vendor = random.choice(vendors)
    date = (datetime.now() - timedelta(days=random.randint(0, 90))).strftime('%Y-%m-%d')
    amount = round(random.uniform(500.0, 10000.0), 2)
    
    html_content = f"""
    <html>
    <head>
        <style>
            body {{ font-family: Arial, sans-serif; margin: 40px; }}
            .header {{ display: flex; justify-content: space-between; margin-bottom: 40px; }}
            .invoice-title {{ font-size: 24px; font-weight: bold; color: #333; }}
            .details {{ margin-bottom: 20px; }}
            .table {{ width: 100%; border-collapse: collapse; margin-top: 20px; }}
            .table th, .table td {{ border: 1px solid #ddd; padding: 12px; text-align: left; }}
            .table th {{ background-color: #f2f2f2; }}
            .total {{ text-align: right; margin-top: 20px; font-size: 18px; font-weight: bold; }}
            .footer {{ margin-top: 50px; font-size: 12px; color: #777; text-align: center; }}
        </style>
    </head>
    <body>
        <div class="header">
            <div>
                <div class="invoice-title">INVOICE</div>
                <div>#{invoice_id}</div>
                <div>Date: {date}</div>
            </div>
            <div style="text-align: right;">
                <strong>{vendor['name']}</strong><br>
                {vendor['address']}
            </div>
        </div>
        
        <div class="details">
            <strong>Bill To:</strong><br>
            Contoso Financial Services<br>
            123 Finance Dr<br>
            New York, NY 10001
        </div>

        <table class="table">
            <thead>
                <tr>
                    <th>Description</th>
                    <th>Quantity</th>
                    <th>Unit Price</th>
                    <th>Total</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>{vendor['name']} Services / Products</td>
                    <td>1</td>
                    <td>${amount}</td>
                    <td>${amount}</td>
                </tr>
            </tbody>
        </table>

        <div class="total">
            Total Due: ${amount}
        </div>

        <div class="footer">
            Payment is due within 30 days. Thank you for your business.
        </div>
    </body>
    </html>
    """
    
    filename = f"test_data/invoices/Invoice_{invoice_id}.html"
    with open(filename, "w") as f:
        f.write(html_content)
    print(f"Generated {filename}")

# Generate 10 invoices
for i in range(10):
    generate_invoice(f"INV-{random.randint(1000, 9999)}")
