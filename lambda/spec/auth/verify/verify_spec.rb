require 'spec_helper'

RSpec.describe 'Verify Signup Endpoint' do
  before(:all) do
    load 'shared/db_client.rb'
    load 'auth/verify/handler.rb'
  end

  before(:each) do
    # Mock Cognito client
    @cognito_client = double('Aws::CognitoIdentityProvider::Client')
    allow(Aws::CognitoIdentityProvider::Client).to receive(:new).and_return(@cognito_client)
  end
  let(:verify_handler) { 'auth/verify/handler.lambda_handler' }

  before(:each) do
    # Mock Cognito client
    @cognito_client = double('Aws::CognitoIdentityProvider::Client')
    allow(Aws::CognitoIdentityProvider::Client).to receive(:new).and_return(@cognito_client)
  end

  describe 'successful verification' do
    it 'verifies email successfully' do
      allow(@cognito_client).to receive(:confirm_sign_up).and_return(true)

      event = {
        'body' => {
          'email' => 'user@example.com',
          'verificationCode' => '123456'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(200)
      response_body = JSON.parse(result['body'])
      expect(response_body['message']).to include('Email verified successfully')
      expect(response_body['email']).to eq('user@example.com')
    end

  end

  describe 'validation errors' do
    it 'requires email' do
      event = {
        'body' => {
          'verificationCode' => '123456'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Email is required')
    end

    it 'requires verification code' do
      event = {
        'body' => {
          'email' => 'user@example.com'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Verification code is required')
    end
  end

  describe 'Cognito errors' do
    it 'handles invalid verification code' do
      allow(@cognito_client).to receive(:confirm_sign_up).and_raise(
        Aws::CognitoIdentityProvider::Errors::CodeMismatchException.new(nil, 'Invalid code')
      )

      event = {
        'body' => {
          'email' => 'user@example.com',
          'verificationCode' => 'wrong'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('InvalidCode')
    end

    it 'handles expired verification code' do
      allow(@cognito_client).to receive(:confirm_sign_up).and_raise(
        Aws::CognitoIdentityProvider::Errors::ExpiredCodeException.new(nil, 'Code expired')
      )

      event = {
        'body' => {
          'email' => 'user@example.com',
          'verificationCode' => '123456'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ExpiredCode')
    end

    it 'handles user not found' do
      allow(@cognito_client).to receive(:confirm_sign_up).and_raise(
        Aws::CognitoIdentityProvider::Errors::UserNotFoundException.new(nil, 'User not found')
      )

      event = {
        'body' => {
          'email' => 'nonexistent@example.com',
          'verificationCode' => '123456'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(404)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('UserNotFound')
    end

    it 'handles too many failed attempts' do
      allow(@cognito_client).to receive(:confirm_sign_up).and_raise(
        Aws::CognitoIdentityProvider::Errors::TooManyFailedAttemptsException.new(nil, 'Too many attempts')
      )

      event = {
        'body' => {
          'email' => 'user@example.com',
          'verificationCode' => '123456'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(429)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('TooManyAttempts')
    end
  end
end
