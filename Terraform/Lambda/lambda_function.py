import json
import boto3
import time
from datetime import datetime

athena_client = boto3.client('athena')
s3_client = boto3.client('s3')
s3_bucket_name = "my-data-bucket-terraform-example"
database_name = "bellybrewanalysis_db"

def create_table():
    query = f"""
        CREATE EXTERNAL TABLE IF NOT EXISTS {database_name}.raw_data (
            CaskID string,
            CaskName string,
            CaskType string,
            KombuchaFlavor string,
            Lactobacillus bigint,
            Acetobacter bigint,
            Gluconobacter bigint,
            `PH Level` double,
            `LS-Code` string,
            Weight double,
            Temperature double
        )
        ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
        WITH SERDEPROPERTIES (
            'separatorChar' = ',',
            'quoteChar' = '"'
        )
        STORED AS TEXTFILE
        LOCATION 's3://{s3_bucket_name}/raw/'
        TBLPROPERTIES ('has_encrypted_data'='false',
            'skip.header.line.count' = '1'
        );
    """
    response = athena_client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': database_name},
        ResultConfiguration={'OutputLocation': f's3://{s3_bucket_name}/athena/'}
    )
    query_execution_id = response['QueryExecutionId']
    query_status = None
    while query_status != 'SUCCEEDED':
        query_status_response = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
        query_status = query_status_response['QueryExecution']['Status']['State']
        if query_status == 'FAILED':
            raise Exception('Query failed to run.')
        elif query_status == 'CANCELLED':
            raise Exception('Query was cancelled.')
        time.sleep(5)
    return

def lambda_handler(event, context):
    current_date = datetime.now().strftime("%Y-%m-%d")
    create_table()
    query = f"""
        SELECT * FROM "{database_name}"."raw_data"
        WHERE ("PH Level" < 2.5 or "PH Level" > 3.5)
        AND "$path" like '%{current_date}%';
        """
    response = athena_client.start_query_execution(
        QueryString=query,
        QueryExecutionContext={'Database': database_name},
        ResultConfiguration={'OutputLocation': f's3://{s3_bucket_name}/processed/{current_date}/'}
    )
    query_execution_id = response['QueryExecutionId']
    query_status = None
    while query_status != 'SUCCEEDED':
        query_status_response = athena_client.get_query_execution(QueryExecutionId=query_execution_id)
        query_status = query_status_response['QueryExecution']['Status']['State']
        if query_status == 'FAILED':
            raise Exception('Query failed to run.')
        elif query_status == 'CANCELLED':
            raise Exception('Query was cancelled.')
        time.sleep(5)
    result_s3_location = f's3://{s3_bucket_name}/processed/{current_date}/' + query_execution_id + '.csv'
    return {
        'statusCode': 200,
        'body': json.dumps({
            'message': 'Query executed successfully!',
            'result_s3_location': result_s3_location
        })
    }