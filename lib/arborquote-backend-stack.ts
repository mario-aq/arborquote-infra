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
import * as cognito from 'aws-cdk-lib/aws-cognito';

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

    // Companies Table
    const companiesTable = new dynamodb.Table(this, 'CompaniesTable', {
      tableName: `ArborQuote-Companies-${stage}`,
      partitionKey: {
        name: 'companyId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: false,
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

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

    // Add GSI for querying users by companyId
    usersTable.addGlobalSecondaryIndex({
      indexName: 'companyId-index',
      partitionKey: {
        name: 'companyId',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
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

    // ShortLinks Table for PDF short URLs
    const shortLinksTable = new dynamodb.Table(this, 'ShortLinksTable', {
      tableName: `ArborQuote-ShortLinks-${stage}`,
      partitionKey: {
        name: 'slug',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST, // Free tier friendly
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
      pointInTimeRecovery: false, // Disable to save cost
      encryption: dynamodb.TableEncryption.AWS_MANAGED,
    });

    // Add GSI for querying by quoteId and locale (for cleanup when quote deleted)
    shortLinksTable.addGlobalSecondaryIndex({
      indexName: 'quoteId-locale-index',
      partitionKey: {
        name: 'quoteId',
        type: dynamodb.AttributeType.STRING,
      },
      sortKey: {
        name: 'locale',
        type: dynamodb.AttributeType.STRING,
      },
      projectionType: dynamodb.ProjectionType.ALL,
    });

    // ========================================
    // Cognito User Pool for Authentication
    // ========================================

    const userPool = new cognito.UserPool(this, 'UserPool', {
      userPoolName: `ArborQuote-${stage}`,
      selfSignUpEnabled: true,
      signInAliases: { email: true },
      passwordPolicy: {
        minLength: 8,
        requireLowercase: true,
        requireUppercase: true,
        requireDigits: true,
        requireSymbols: false,
      },
      removalPolicy: stage === 'prod' ? cdk.RemovalPolicy.RETAIN : cdk.RemovalPolicy.DESTROY,
    });

    const userPoolClient = new cognito.UserPoolClient(this, 'UserPoolClient', {
      userPool,
      authFlows: {
        userPassword: true,
        userSrp: true,
        adminUserPassword: true,
      },
      accessTokenValidity: cdk.Duration.hours(1),
      idTokenValidity: cdk.Duration.hours(1),
      refreshTokenValidity: cdk.Duration.days(30),
      preventUserExistenceErrors: true,
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
        COMPANIES_TABLE_NAME: companiesTable.tableName,
        PHOTOS_BUCKET_NAME: photosBucket.bucketName,
        PDF_BUCKET_NAME: pdfsBucket.bucketName,
        SHORT_LINKS_TABLE_NAME: shortLinksTable.tableName,
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
      memorySize: 512, // Higher for Prawn PDF generation + GPT polish
      timeout: cdk.Duration.seconds(120), // Longer for GPT polish + PDF generation
      environment: {
        ...commonLambdaProps.environment,
        VERSION: '1.2.0', // Force Lambda update
        OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
        OPENAI_GPT_MODEL: process.env.OPENAI_GPT_MODEL || 'gpt-4o-mini',
      },
    });

    // Short link redirect Lambda
    const shortLinkRedirectFunction = new lambda.Function(this, 'ShortLinkRedirectFunction', {
      ...commonLambdaProps,
      functionName: `ArborQuote-ShortLinkRedirect-${stage}`,
      code: lambda.Code.fromAsset('lambda', {
        bundling: {
          image: lambda.Runtime.RUBY_3_2.bundlingImage,
          command: [
            'bash', '-c',
            'cp -r . /asset-output/'
          ],
        },
      }),
      handler: 'short_link_redirect/handler.lambda_handler',
      environment: {
        ...commonLambdaProps.environment,
        PRESIGNED_TTL_SECONDS: '3600', // 1 hour (short links auto-refresh)
      },
    });

    // Voice interpret Lambda (no DB access needed - stateless)
    const voiceInterpretFunction = new lambda.Function(this, 'VoiceInterpretFunction', {
      ...commonLambdaProps,
      functionName: `ArborQuote-VoiceInterpret-${stage}`,
      code: lambda.Code.fromAsset('lambda', {
        bundling: {
          image: lambda.Runtime.RUBY_3_2.bundlingImage,
          command: [
            'bash', '-c',
            'cp -r . /asset-output/'
          ],
        },
      }),
      handler: 'voice_interpret/handler.lambda_handler',
      memorySize: 512, // Higher for audio processing
      timeout: cdk.Duration.seconds(60), // Whisper (~2-5s) + GPT (~10-30s) can take time
      environment: {
        ...commonLambdaProps.environment,
        OPENAI_API_KEY: process.env.OPENAI_API_KEY || '',
        OPENAI_TRANSCRIBE_MODEL: 'whisper-1',
        OPENAI_GPT_MODEL: process.env.OPENAI_GPT_MODEL || 'gpt-4o-mini',
      },
    });

    // ========================================
    // Authentication Lambda Functions
    // ========================================

    // Login Lambda
    const loginFunction = new lambda.Function(this, 'LoginFunction', {
      ...commonLambdaProps,
      functionName: `ArborQuote-Login-${stage}`,
      code: lambda.Code.fromAsset('lambda', {
        bundling: {
          image: lambda.Runtime.RUBY_3_2.bundlingImage,
          command: [
            'bash', '-c',
            'cp -r . /asset-output/'
          ],
        },
      }),
      handler: 'auth/login/handler.lambda_handler',
      memorySize: 256,
      timeout: cdk.Duration.seconds(30),
      environment: {
        ...commonLambdaProps.environment,
        AWS_REGION: cdk.Stack.of(this).region,
        COGNITO_USER_POOL_ID: userPool.userPoolId,
        COGNITO_CLIENT_ID: userPoolClient.userPoolClientId,
      },
    });

    // Signup Lambda
    const signupFunction = new lambda.Function(this, 'SignupFunction', {
      ...commonLambdaProps,
      functionName: `ArborQuote-Signup-${stage}`,
      code: lambda.Code.fromAsset('lambda', {
        bundling: {
          image: lambda.Runtime.RUBY_3_2.bundlingImage,
          command: [
            'bash', '-c',
            'cp -r . /asset-output/'
          ],
        },
      }),
      handler: 'auth/signup/handler.lambda_handler',
      memorySize: 256,
      timeout: cdk.Duration.seconds(30),
      environment: {
        ...commonLambdaProps.environment,
        AWS_REGION: cdk.Stack.of(this).region,
        COGNITO_USER_POOL_ID: userPool.userPoolId,
        COGNITO_CLIENT_ID: userPoolClient.userPoolClientId,
        AUTO_CONFIRM_USERS: stage === 'dev' ? 'true' : 'false', // Auto-confirm in dev
      },
    });

    // Token Refresh Lambda
    const refreshFunction = new lambda.Function(this, 'RefreshFunction', {
      ...commonLambdaProps,
      functionName: `ArborQuote-Refresh-${stage}`,
      code: lambda.Code.fromAsset('lambda', {
        bundling: {
          image: lambda.Runtime.RUBY_3_2.bundlingImage,
          command: [
            'bash', '-c',
            'cp -r . /asset-output/'
          ],
        },
      }),
      handler: 'auth/refresh/handler.lambda_handler',
      memorySize: 256,
      timeout: cdk.Duration.seconds(30),
      environment: {
        ...commonLambdaProps.environment,
        AWS_REGION: cdk.Stack.of(this).region,
        COGNITO_USER_POOL_ID: userPool.userPoolId,
        COGNITO_CLIENT_ID: userPoolClient.userPoolClient.userPoolClientId,
      },
    });

    // Grant Cognito permissions to auth functions
    userPool.grant(loginFunction, 'cognito-idp:AdminInitiateAuth');
    userPool.grant(signupFunction, 'cognito-idp:SignUp', 'cognito-idp:AdminConfirmSignUp');
    userPool.grant(refreshFunction, 'cognito-idp:AdminInitiateAuth');

    // Grant DynamoDB permissions (least privilege)
    quotesTable.grantWriteData(createQuoteFunction); // PutItem
    quotesTable.grantReadData(listQuotesFunction); // Query (on GSI)
    quotesTable.grantReadData(getQuoteFunction); // GetItem
    quotesTable.grantReadWriteData(updateQuoteFunction); // UpdateItem + GetItem
    quotesTable.grantReadWriteData(deleteQuoteFunction); // GetItem + DeleteItem
    quotesTable.grantReadWriteData(generatePdfFunction); // GetItem + UpdateItem for PDF metadata
    
    // Grant Users and Companies table permissions
    usersTable.grantReadData(generatePdfFunction); // GetItem for provider info
    companiesTable.grantReadData(generatePdfFunction); // GetItem for company info

    // Grant ShortLinks table permissions
    shortLinksTable.grantReadWriteData(generatePdfFunction); // Create/update short links on PDF generation
    shortLinksTable.grantReadWriteData(deleteQuoteFunction); // Delete short links on quote deletion
    shortLinksTable.grantReadWriteData(shortLinkRedirectFunction); // Read and update presigned URLs

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
    pdfsBucket.grantRead(shortLinkRedirectFunction); // Generate presigned URLs for redirects

    // ========================================
    // API Gateway (HTTP API)
    // ========================================

    // Import existing hosted zone for arborquote.app
    const hostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'ArborQuoteHostedZone', {
      hostedZoneId: 'Z080480827AH38E8EVHQD',
      zoneName: 'arborquote.app',
    });

    // Import hosted zone for aquote.link (short link domain)
    const shortLinkHostedZone = route53.HostedZone.fromHostedZoneAttributes(this, 'ShortLinkHostedZone', {
      hostedZoneId: 'Z07757922GRBBC1G5FWK8',
      zoneName: 'aquote.link',
    });

    // Create SSL certificate for api.arborquote.app
    const certificate = new certificatemanager.Certificate(this, 'ApiCertificate', {
      domainName: stage === 'prod' ? 'api.arborquote.app' : `api-${stage}.arborquote.app`,
      validation: certificatemanager.CertificateValidation.fromDns(hostedZone),
    });

    // Create SSL certificate for aquote.link
    const shortLinkCertificate = new certificatemanager.Certificate(this, 'ShortLinkCertificate', {
      domainName: 'aquote.link',
      validation: certificatemanager.CertificateValidation.fromDns(shortLinkHostedZone),
    });

    // Create custom domain name for API
    const domainName = new apigatewayv2.DomainName(this, 'ApiDomainName', {
      domainName: stage === 'prod' ? 'api.arborquote.app' : `api-${stage}.arborquote.app`,
      certificate: certificate,
    });

    // Create custom domain name for short links
    const shortLinkDomainName = new apigatewayv2.DomainName(this, 'ShortLinkDomainName', {
      domainName: 'aquote.link',
      certificate: shortLinkCertificate,
    });

    const httpApi = new apigatewayv2.HttpApi(this, 'ArborQuoteApi', {
      apiName: `ArborQuote-API-${stage}`,
      description: `ArborQuote MVP Backend API (${stage}) with short links`,
      defaultDomainMapping: {
        domainName: domainName,
      },
      corsPreflight: {
        allowOrigins: [
          'https://arborquote.app',
          'https://www.arborquote.app',
          'https://app.arborquote.app',
          'https://dev.arborquote.app',
        ],
        allowCredentials: false, // No authentication implemented yet
        allowMethods: [
          apigatewayv2.CorsHttpMethod.GET,
          apigatewayv2.CorsHttpMethod.POST,
          apigatewayv2.CorsHttpMethod.PUT,
          apigatewayv2.CorsHttpMethod.DELETE,
          apigatewayv2.CorsHttpMethod.OPTIONS,
        ],
        allowHeaders: ['Content-Type', 'Authorization'],
        maxAge: cdk.Duration.hours(1),
      },
    });

    // Note: JWT authentication is handled in Lambda functions
    // API Gateway level JWT validation removed due to CDK version limitations

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

    const shortLinkRedirectIntegration = new HttpLambdaIntegration(
      'ShortLinkRedirectIntegration',
      shortLinkRedirectFunction
    );

    const voiceInterpretIntegration = new HttpLambdaIntegration(
      'VoiceInterpretIntegration',
      voiceInterpretFunction
    );

    // Auth integrations (no auth required)
    const loginIntegration = new HttpLambdaIntegration(
      'LoginIntegration',
      loginFunction
    );

    const signupIntegration = new HttpLambdaIntegration(
      'SignupIntegration',
      signupFunction
    );

    const refreshIntegration = new HttpLambdaIntegration(
      'RefreshIntegration',
      refreshFunction
    );

    // Add routes

    // Auth routes (no authentication required)
    httpApi.addRoutes({
      path: '/auth/login',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: loginIntegration,
    });

    httpApi.addRoutes({
      path: '/auth/signup',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: signupIntegration,
    });

    httpApi.addRoutes({
      path: '/auth/refresh',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: refreshIntegration,
    });

    // API routes (authentication handled in Lambda functions)
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

    httpApi.addRoutes({
      path: '/q/{slug}',
      methods: [apigatewayv2.HttpMethod.GET],
      integration: shortLinkRedirectIntegration,
    });

    httpApi.addRoutes({
      path: '/quotes/voice-interpret',
      methods: [apigatewayv2.HttpMethod.POST],
      integration: voiceInterpretIntegration,
    });

    // Map short link domain to the API
    new apigatewayv2.ApiMapping(this, 'ShortLinkApiMapping', {
      api: httpApi,
      domainName: shortLinkDomainName,
      stage: httpApi.defaultStage,
    });

    // Create Route 53 A record pointing to API Gateway for main API domain
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

    // Create Route 53 A record for aquote.link (apex domain)
    new route53.ARecord(this, 'ShortLinkAliasRecord', {
      zone: shortLinkHostedZone,
      recordName: '', // Apex domain
      target: route53.RecordTarget.fromAlias(
        new route53Targets.ApiGatewayv2DomainProperties(
          shortLinkDomainName.regionalDomainName,
          shortLinkDomainName.regionalHostedZoneId
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

    new cdk.CfnOutput(this, 'CompaniesTableName', {
      value: companiesTable.tableName,
      description: 'DynamoDB Companies table name',
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

    new cdk.CfnOutput(this, 'ShortLinksTableName', {
      value: shortLinksTable.tableName,
      description: 'DynamoDB ShortLinks table name',
    });

    new cdk.CfnOutput(this, 'ShortLinkDomain', {
      value: 'https://aquote.link',
      description: 'Short link domain for PDF sharing',
    });

    // Cognito outputs for frontend authentication
    new cdk.CfnOutput(this, 'UserPoolId', {
      value: userPool.userPoolId,
      description: 'Cognito User Pool ID',
    });

    new cdk.CfnOutput(this, 'UserPoolClientId', {
      value: userPoolClient.userPoolClientId,
      description: 'Cognito User Pool Client ID',
    });

    new cdk.CfnOutput(this, 'UserPoolRegion', {
      value: this.region,
      description: 'AWS Region for Cognito',
    });
  }
}

