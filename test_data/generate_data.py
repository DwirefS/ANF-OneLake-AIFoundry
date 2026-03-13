import csv
import os
import random
from datetime import datetime, timedelta

# Ensure directory exists
os.makedirs('test_data/financial_statements', exist_ok=True)

# Generate Dummy Financial Statement (CSV)
def generate_csv(filename, rows=50):
    with open(filename, 'w', newline='') as csvfile:
        fieldnames = ['Date', 'TransactionID', 'Vendor', 'Category', 'Amount', 'Description', 'Status']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        writer.writeheader()
        vendors = ['Azure Cloud Services', 'OfficeMax', 'WeWork', 'Dell Computers', 'Staffing Agency', 'Salesforce', 'Slack', 'Zoom']
        categories = ['Cloud Infrastructure', 'Office Supplies', 'Rent', 'Hardware', 'Personnel', 'Software License', 'Communication', 'Services']
        
        for i in range(rows):
            date = (datetime.now() - timedelta(days=random.randint(0, 365))).strftime('%Y-%m-%d')
            writer.writerow({
                'Date': date,
                'TransactionID': f'TRX-{random.randint(10000, 99999)}',
                'Vendor': random.choice(vendors),
                'Category': random.choice(categories),
                'Amount': round(random.uniform(100.0, 5000.0), 2),
                'Description': f'Payment for {random.choice(categories)} services to {random.choice(vendors)}',
                'Status': 'Posted'
            })

generate_csv('test_data/financial_statements/Q1_2025_Expenses.csv')
generate_csv('test_data/financial_statements/Q2_2025_Expenses.csv')
print("CSV generation complete.")
