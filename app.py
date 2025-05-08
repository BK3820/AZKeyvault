from flask import Flask, render_template
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient
import pyodbc

app = Flask(__name__)

# Configure Key Vault
key_vault_url = "https://Vault-test-ca-cen.vault.azure.net/"
credential = DefaultAzureCredential()
secret_client = SecretClient(vault_url=key_vault_url, credential=credential)

# Retrieve database connection string
db_connection_string = secret_client.get_secret("DbConnectionString").value

def get_db_connection():
    return pyodbc.connect(db_connection_string)

@app.route('/')
def index():
    try:
        # Connect to the database
        conn = get_db_connection()
        cursor = conn.cursor()
        
        # Query a sample table (e.g., Users)
        cursor.execute("SELECT * FROM Users")
        columns = [column[0] for column in cursor.description]
        rows = cursor.fetchall()
        
        # Close connection
        cursor.close()
        conn.close()
        
        return render_template('index.html', columns=columns, rows=rows, connection_string=db_connection_string)
    except Exception as e:
        return render_template('error.html', error=str(e))

if __name__ == '__main__':
    app.run(debug=True)