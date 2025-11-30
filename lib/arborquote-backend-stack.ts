import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as apigatewayv2 from 'aws-cdk-lib/aws-apigatewayv2';
import { HttpLambdaIntegration } from 'aws-cdk-lib/aws-apigatewayv2-integrations';
import * as logs from 'aws-cdk-lib/aws-logs';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as route53Targets from 'aws-cdk-lib/aws-route53-targets';
import * as certificatemanager from 'aws-cdk-lib/aws-certificatemanager';

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
    // S3 Bucket for Photos
    // ========================================

    const photosBucket = new s3.Bucket(this, 'PhotosBucket', {
      bucketName: `arborquote-photos-${stage}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Private bucket
      versioned: false, // Cost optimization
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: stage !== 'prod', // Auto-delete on stack destroy (non-prod only)
      lifecycleRules: [
        {
          id: 'move-to-glacier-after-90-days',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(90),
            },
          ],
        },
      ],
      cors: [
        {
          allowedMethods: [
            s3.HttpMethods.GET,
            s3.HttpMethods.PUT,
            s3.HttpMethods.POST,
          ],
          allowedOrigins: ['*'], // Configure properly in production
          allowedHeaders: ['*'],
          maxAge: 3000,
        },
      ],
    });

    // ========================================
    // S3 Bucket for PDFs
    // ========================================

    const pdfsBucket = new s3.Bucket(this, 'PdfsBucket', {
      bucketName: `arborquote-quote-pdfs-${stage}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL, // Private bucket
      versioned: false, // Cost optimization
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: stage !== 'prod', // Auto-delete on stack destroy (non-prod only)
      lifecycleRules: [
        {
          id: 'move-to-ia-after-30-days',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.INFREQUENT_ACCESS,
              transitionAfter: cdk.Duration.days(30),
            },
          ],
        },
      ],
    });

    // ========================================
    // Lambda Functions (Ruby 3.2)
    // ========================================

    // Common Lambda configuration for all functions
    const commonLambdaProps = {
      runtime: lambda.Runtime.RUBY_3_2,
      architecture: lambda.Architecture.ARM_64, // Graviton2 for lower cost
      timeout: cdk.Duration.seconds(30), // Increased for photo uploads
      memorySize: 256, // Increased for base64 decoding
      environment: {
        QUOTES_TABLE_NAME: quotesTable.tableName,
        USERS_TABLE_NAME: usersTable.tableName,
        PHOTOS_BUCKET_NAME: photosBucket.bucketName,
        PDF_BUCKET_NAME: pdfsBucket.bucketName,
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
    const deleteQuoteFunction = createLambdaFunction('DeleteQuote', 'delete_quote');
    const uploadPhotoFunction = createLambdaFunction('UploadPhoto', 'upload_photo');
    const deletePhotoFunction = createLambdaFunction('DeletePhoto', 'delete_photo');
    
    // Generate PDF Lambda with increased memory and timeout for PDF generation
    const generatePdfFunction = new lambda.Function(this, 'GeneratePdfFunction', {
      ...commonLambdaProps,
      functionName: `ArborQuote-GeneratePdf-${stage}`,
      code: lambda.Code.fromAsset('lambda', {
        bundling: {
          image: lambda.Runtime.RUBY_3_2.bundlingImage,
          command: [
            'bash', '-c',
            'cp -r . /asset-output/'
          ],
        },
      }),
      handler: 'generate_pdf/handler.lambda_handler',
      memorySize: 512, // Higher for Prawn PDF generation
      timeout: cdk.Duration.seconds(60), // Longer for PDF generation
    });

    // Grant DynamoDB permissions (least privilege)
    quotesTable.grantWriteData(createQuoteFunction); // PutItem
    quotesTable.grantReadData(listQuotesFunction); // Query (on GSI)
    quotesTable.grantReadData(getQuoteFunction); // GetItem
    quotesTable.grantReadWriteData(updateQuoteFunction); // UpdateItem + GetItem
    quotesTable.grantReadWriteData(deleteQuoteFunction); // GetItem + DeleteItem
    quotesTable.grantReadWriteData(generatePdfFunction); // GetItem + UpdateItem for PDF metadata

    // Grant S3 permissions (least privilege)
    photosBucket.grantPut(createQuoteFunction); // Upload photos on create
    photosBucket.grantPut(updateQuoteFunction); // Upload photos on update
    photosBucket.grantDelete(updateQuoteFunction); // Delete photos when items removed
    photosBucket.grantReadWrite(deleteQuoteFunction); // Delete all photos when quote deleted
    // Explicitly grant ListBucket for delete_item_photos function
    updateQuoteFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ['s3:ListBucket'],
      resources: [photosBucket.bucketArn],
    }));
    deleteQuoteFunction.addToRolePolicy(new iam.PolicyStatement({
      actions: ['s3:ListBucket'],
      resources: [photosBucket.bucketArn],
    }));
    photosBucket.grantRead(getQuoteFunction); // Generate presigned URLs
    photosBucket.grantRead(listQuotesFunction); // Generate presigned URLs
    photosBucket.grantPut(uploadPhotoFunction); // Upload photos independently
    photosBucket.grantDelete(deletePhotoFunction); // Delete photos independently
    
    // PDF bucket permissions
    pdfsBucket.grantReadWrite(generatePdfFunction); // Generate and store PDFs
    pdfsBucket.grantDelete(deleteQuoteFunction); // Delete PDFs when quote deleted

    // ========================================
    // API Gateway (HTTP API)
    // ========================================

    // Import existing hosted zone
    const hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'ArborQuoteHostedZone', {
      hostedZoneId: 'Z080480827AH38E8EVHQD',
      zoneName: 'arborquote.app',
    });

    // Create SSL certificate for api.arborquote.app
    const certificate = new certificatemanager.Certificate(this, 'ApiCertificate', {
      domainName: stage === 'prod' ? 'api.arborquote.app' : `api-${stage}.arborquote.app`,
      validation: certificatemanager.CertificateValidation.fromDns(hostedZone),
    });

    // Create custom domain name
    const domainName = new apigatewayv2.DomainName(this, 'ApiDomainName', {
      domainName: stage === 'prod' ? 'api.arborquote.app' : `api-${stage}.arborquote.app`,
      certificate: certificate,
    });

    const httpApi = new apigatewayv2.HttpApi(this, 'ArborQuoteApi', {
      apiName: `ArborQuote-API-${stage}`,
      description: `ArborQuote MVP Backend API (${stage})`,
      defaultDomainMapping: {
        domainName: domainName,
      },
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
    const createQuoteIntegration = new HttpLambdaIntegration(
      'CreateQuoteIntegration',
      createQuoteFunction
    );

    const listQuotesIntegration = new HttpLambdaIntegration(
      'ListQuotesIntegration',
      listQuotesFunction
    );

    const getQuoteIntegration = new HttpLambdaIntegration(
      'GetQuoteIntegration',
      getQuoteFunction
    );

    const updateQuoteIntegration = new HttpLambdaIntegration(
      'UpdateQuoteIntegration',
      updateQuoteFunction
    );

    const deleteQuoteIntegration = new HttpLambdaIntegration(
      'DeleteQuoteIntegration',
      deleteQuoteFunction
    );

    const uploadPhotoIntegration = new HttpLambdaIntegration(
      'UploadPhotoIntegration',
      uploadPhotoFunction
    );

    const deletePhotoIntegration = new HttpLambdaIntegration(
      'DeletePhotoIntegration',
      deletePhotoFunction
    );

    const generatePdfIntegration = new HttpLambdaIntegration(
      'GeneratePdfIntegration',
      generatePdfFunction
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

    httpApi.addRoutes({
      path: '/quotes/{quoteId}',
      methods: [apigatewayv2.HttpMethod.DELETE],
      integration: deleteQuoteIntegration,
    });

    httpApi.addRoutes({
      path: '/photos',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: uploadPhotoIntegration,
    });

    httpApi.addRoutes({
      path: '/photos',
      methods: [apigatewayv2.HttpMethod.DELETE],
      integration: deletePhotoIntegration,
    });

    httpApi.addRoutes({
      path: '/quotes/{quoteId}/pdf',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: generatePdfIntegration,
    });

    // Create Route 53 A record pointing to API Gateway
    new route53.ARecord(this, 'ApiAliasRecord', {
      zone: hostedZone,
      recordName: stage === 'prod' ? 'api' : `api-${stage}`,
      target: route53.RecordTarget.fromAlias(
        new route53Targets.ApiGatewayv2DomainProperties(
          domainName.regionalDomainName,
          domainName.regionalHostedZoneId
        )
      ),
    });

    // ========================================
    // Outputs
    // ========================================

    new cdk.CfnOutput(this, 'ApiEndpoint', {
      value: httpApi.apiEndpoint,
      description: 'HTTP API Gateway endpoint URL (CloudFront)',
      exportName: `ArborQuoteApiEndpoint-${stage}`,
    });

    new cdk.CfnOutput(this, 'CustomDomain', {
      value: `https://${stage === 'prod' ? 'api.arborquote.app' : `api-${stage}.arborquote.app`}`,
      description: 'Custom domain for API',
      exportName: `ArborQuoteCustomDomain-${stage}`,
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

    new cdk.CfnOutput(this, 'PhotosBucketName', {
      value: photosBucket.bucketName,
      description: 'S3 bucket for quote photos',
    });

    new cdk.CfnOutput(this, 'PdfsBucketName', {
      value: pdfsBucket.bucketName,
      description: 'S3 bucket for quote PDFs',
    });
  }
}

