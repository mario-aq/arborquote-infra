require 'spec_helper'

RSpec.describe 'Challenge Response Endpoint' do
  before(:all) do
    load 'shared/db_client.rb'
    load 'auth/challenge/handler.rb'
  end

  before(:each) do
    # Mock Cognito client
    @cognito_client = double('Aws::CognitoIdentityProvider::Client')
    allow(Aws::CognitoIdentityProvider::Client).to receive(:new).and_return(@cognito_client)
  end

  describe 'successful challenge response' do
    it 'handles NEW_PASSWORD_REQUIRED challenge successfully' do
      auth_result = {
        access_token: 'access_token',
        refresh_token: 'refresh_token',
        id_token: 'id_token',
        expires_in: 3600
      }

      allow(@cognito_client).to receive(:respond_to_auth_challenge).and_return(
        double(authentication_result: auth_result)
      )

      event = {
        'body' => {
          'username' => 'admin@example.com',
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'challengeResponse' => { 'NEW_PASSWORD' => 'newpassword123' },
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(200)
      response_body = JSON.parse(result['body'])
      expect(response_body['message']).to eq('Authentication successful')
    end
  end

  describe 'validation errors' do
    it 'requires username' do
      event = {
        'body' => {
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'challengeResponse' => { 'NEW_PASSWORD' => 'password123' },
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Username is required')
    end

    it 'requires challenge name' do
      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeResponse' => { 'NEW_PASSWORD' => 'password123' },
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Challenge name is required')
    end

    it 'requires challenge response object' do
      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Challenge response must be an object')
    end

    it 'requires session token' do
      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'challengeResponse' => { 'NEW_PASSWORD' => 'password123' }
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('Session token is required')
    end

    it 'requires NEW_PASSWORD for NEW_PASSWORD_REQUIRED challenge' do
      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'challengeResponse' => {},
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('ValidationError')
      expect(response_body['message']).to include('NEW_PASSWORD must be at least 8 characters long')
    end

    it 'rejects unsupported challenge types' do
      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeName' => 'UNSUPPORTED_CHALLENGE',
          'challengeResponse' => { 'CODE' => '123456' },
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(400)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('UnsupportedChallenge')
    end
  end

  describe 'Cognito errors' do
    it 'handles invalid session' do
      allow(@cognito_client).to receive(:respond_to_auth_challenge).and_raise(
        Aws::CognitoIdentityProvider::Errors::NotAuthorizedException.new(nil, 'Invalid session')
      )

      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'challengeResponse' => { 'NEW_PASSWORD' => 'password123' },
          'session' => 'invalid-session'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(401)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('NotAuthorized')
    end

    it 'handles too many failed attempts' do
      allow(@cognito_client).to receive(:respond_to_auth_challenge).and_raise(
        Aws::CognitoIdentityProvider::Errors::TooManyFailedAttemptsException.new(nil, 'Too many attempts')
      )

      event = {
        'body' => {
          'username' => 'user@example.com',
          'challengeName' => 'NEW_PASSWORD_REQUIRED',
          'challengeResponse' => { 'NEW_PASSWORD' => 'password123' },
          'session' => 'session-token'
        }.to_json
      }

      result = send(:lambda_handler, event: event, context: {})

      expect(result['statusCode']).to eq(429)
      response_body = JSON.parse(result['body'])
      expect(response_body['error']).to eq('TooManyAttempts')
    end
  end
end
