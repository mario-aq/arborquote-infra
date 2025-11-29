import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigatewayv2 from 'aws-cdk-lib/aws-apigatewayv2';
import * as apigatewayv2Integrations from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as logs from 'aws-cdk-lib/aws-logs';

interface ArborQuoteBackendStackProps extends cdk.StackProps {
  stage: string;
}

export class ArborQuoteBackendStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: ArborQuoteBackendStackProps) {
    super(scope, id, props);

    const { stage } = props;

    // ========================================
    // DynamoDB Tables
    // ========================================

    // Users Table
    const usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: `ArborQuote-Users-${stage}`,
      partitionKey: {
        name: 'userId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST, // Free tier friendly
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: false, // Disable to save cost
      encryption: dynamodb.TableEncryption.AWS_MANAGED, // Default encryption
    });

    // Quotes Table with GSI for querying by userId
    const quotesTable = new dynamodb.Table(this, 'QuotesTable', {
      tableName: `ArborQuote-Quotes-${stage}`,
      partitionKey: {
        name: 'quoteId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST, // Free tier friendly
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: false, // Disable to save cost
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add GSI for querying quotes by userId
    quotesTable.addGlobalSecondaryIndex({
      indexName: 'userId-index',
      partitionKey: {
        name: 'userId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'createdAt',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // ========================================
    // Lambda Functions (Ruby 3.2)
    // ========================================

    // Common Lambda configuration for all functions
    const commonLambdaProps = {
      runtime: lambda.Runtime.RUBY_3_2,
      architecture: lambda.Architecture.ARM_64, // Graviton2 for lower cost
      timeout: cdk.Duration.seconds(10),
      memorySize: 128, // Minimum for free tier
      environment: {
        QUOTES_TABLE_NAME: quotesTable.tableName,
        USERS_TABLE_NAME: usersTable.tableName,
        STAGE: stage,
      },
      logRetention: logs.RetentionDays.ONE_WEEK, // Short retention for MVP
    };

    // Helper function to create Lambda with shared code
    const createLambdaFunction = (name: string, handlerPath: string) => {
      return new lambda.Function(this, name, {
        ...commonLambdaProps,
        functionName: `ArborQuote-${name}-${stage}`,
        code: lambda.Code.fromAsset('lambda', {
          bundling: {
            image: lambda.Runtime.RUBY_3_2.bundlingImage,
            command: [
              'bash', '-c',
              'cp -r . /asset-output/'
            ],
          },
        }),
        handler: `${handlerPath}/handler.lambda_handler`,
      });
    };

    // Create Lambda functions
    const createQuoteFunction = createLambdaFunction('CreateQuote', 'create_quote');
    const listQuotesFunction = createLambdaFunction('ListQuotes', 'list_quotes');
    const getQuoteFunction = createLambdaFunction('GetQuote', 'get_quote');
    const updateQuoteFunction = createLambdaFunction('UpdateQuote', 'update_quote');

    // Grant DynamoDB permissions (least privilege)
    quotesTable.grantWriteData(createQuoteFunction); // PutItem
    quotesTable.grantReadData(listQuotesFunction); // Query (on GSI)
    quotesTable.grantReadData(getQuoteFunction); // GetItem
    quotesTable.grantReadWriteData(updateQuoteFunction); // UpdateItem + GetItem

    // ========================================
    // API Gateway (HTTP API)
    // ========================================

    const httpApi = new apigatewayv2.HttpApi(this, 'ArborQuoteApi', {
      apiName: `ArborQuote-API-${stage}`,
      description: `ArborQuote MVP Backend API (${stage})`,
      corsPreflight: {
        allowOrigins: ['*'], // Configure properly in production
        allowMethods: [
          apigatewayv2.CorsHttpMethod.GET,
          apigatewayv2.CorsHttpMethod.POST,
          apigatewayv2.CorsHttpMethod.PUT,
          apigatewayv2.CorsHttpMethod.DELETE,
          apigatewayv2.CorsHttpMethod.OPTIONS,
        ],
        allowHeaders: ['Content-Type', 'Authorization'],
        maxAge: cdk.Duration.days(1),
      },
    });

    // Create Lambda integrations
    const createQuoteIntegration = new apigatewayv2Integrations.HttpLambdaIntegration(
      'CreateQuoteIntegration',
      createQuoteFunction
    );

    const listQuotesIntegration = new apigatewayv2Integrations.HttpLambdaIntegration(
      'ListQuotesIntegration',
      listQuotesFunction
    );

    const getQuoteIntegration = new apigatewayv2Integrations.HttpLambdaIntegration(
      'GetQuoteIntegration',
      getQuoteFunction
    );

    const updateQuoteIntegration = new apigatewayv2Integrations.HttpLambdaIntegration(
      'UpdateQuoteIntegration',
      updateQuoteFunction
    );

    // Add routes
    httpApi.addRoutes({
      path: '/quotes',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: createQuoteIntegration,
    });

    httpApi.addRoutes({
      path: '/quotes',
      methods: [apigatewayv2.HttpMethod.GET],
      integration: listQuotesIntegration,
    });

    httpApi.addRoutes({
      path: '/quotes/{quoteId}',
      methods: [apigatewayv2.HttpMethod.GET],
      integration: getQuoteIntegration,
    });

    httpApi.addRoutes({
      path: '/quotes/{quoteId}',
      methods: [apigatewayv2.HttpMethod.PUT],
      integration: updateQuoteIntegration,
    });

    // ========================================
    // Outputs
    // ========================================

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: httpApi.apiEndpoint,
      description: 'HTTP API Gateway endpoint URL',
      exportName: `ArborQuoteApiEndpoint-${stage}`,
    });

    new cdk.CfnOutput(this, 'UsersTableName', {
      value: usersTable.tableName,
      description: 'DynamoDB Users table name',
    });

    new cdk.CfnOutput(this, 'QuotesTableName', {
      value: quotesTable.tableName,
      description: 'DynamoDB Quotes table name',
    });

    new cdk.CfnOutput(this, 'Region', {
      value: cdk.Stack.of(this).region,
      description: 'AWS Region',
    });
  }
}

