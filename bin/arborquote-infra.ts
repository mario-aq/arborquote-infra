#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { ArborQuoteBackendStack } from '../lib/arborquote-backend-stack';

const app = new cdk.App();

// Get context or use defaults
const stage = app.node.tryGetContext('stage') || 'dev';
const region = app.node.tryGetContext('region') || 'us-east-1';

new ArborQuoteBackendStack(app, `ArborQuoteBackendStack-${stage}`, {
  env: {
    region: region,
    // Account will be resolved from AWS credentials
  },
  stage: stage,
  description: `ArborQuote MVP Backend Infrastructure (${stage})`,
});

app.synth();

