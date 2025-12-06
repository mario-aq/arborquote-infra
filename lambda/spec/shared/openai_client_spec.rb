require 'spec_helper'
require 'shared/openai_client'

RSpec.describe OpenAiClient do
  # Mock the OpenAI client
  let(:mock_client) { instance_double(OpenAI::Client) }
  let(:mock_audio) { instance_double('audio') }
  let(:mock_chat) { instance_double('chat') }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(mock_client)
    allow(mock_client).to receive(:audio).and_return(mock_audio)
    allow(mock_client).to receive(:chat).and_return(mock_chat)

    # Reset the memoized client
    OpenAiClient.instance_variable_set(:@client, nil)

    # Set required env vars
    ENV['OPENAI_API_KEY'] = 'test-api-key'
    ENV['OPENAI_GPT_MODEL'] = 'gpt-4o-mini'
  end

  describe '.polish_text_for_pdf' do
    let(:notes) { 'cliente quiere trabajo urgente' }
    let(:items_text) do
      [
        { index: 0, description: 'arbol grande de roble' },
        { index: 1, description: 'stump grinding needed' }
      ]
    end
    let(:locale) { 'es' }

    context 'when GPT call succeeds' do
      let(:gpt_response) do
        {
          'choices' => [
            {
              'message' => {
                'content' => JSON.generate({
                  notes: 'El cliente desea el trabajo con urgencia.',
                  items: [
                    { index: 0, description: 'Árbol grande de roble' },
                    { index: 1, description: 'Molienda de tocón necesaria' }
                  ]
                })
              }
            }
          ]
        }
      end

      before do
        allow(mock_client).to receive(:chat).and_return(gpt_response)
      end

      it 'returns polished text in target locale' do
        result = described_class.polish_text_for_pdf(
          notes: notes,
          items_text: items_text,
          locale: locale
        )

        expect(result[:notes]).to eq('El cliente desea el trabajo con urgencia.')
        expect(result[:items].length).to eq(2)
        expect(result[:items][0][:description]).to eq('Árbol grande de roble')
        expect(result[:items][1][:description]).to eq('Molienda de tocón necesaria')
      end

      it 'calls GPT with correct parameters' do
        expect(mock_client).to receive(:chat).with(
          parameters: hash_including(
            model: 'gpt-4o-mini',
            temperature: 0.3,
            response_format: { type: 'json_object' }
          )
        ).and_return(gpt_response)

        described_class.polish_text_for_pdf(
          notes: notes,
          items_text: items_text,
          locale: locale
        )
      end
    end

    context 'when notes and items are empty' do
      it 'returns original text without calling GPT' do
        expect(mock_client).not_to receive(:chat)

        result = described_class.polish_text_for_pdf(
          notes: '',
          items_text: [{ index: 0, description: '' }],
          locale: 'en'
        )

        expect(result[:notes]).to eq('')
        expect(result[:items][0][:description]).to eq('')
      end
    end

    context 'when GPT returns empty response' do
      before do
        allow(mock_client).to receive(:chat).and_return({
          'choices' => [{ 'message' => { 'content' => '' } }]
        })
      end

      it 'raises PolishError' do
        expect {
          described_class.polish_text_for_pdf(
            notes: notes,
            items_text: items_text,
            locale: locale
          )
        }.to raise_error(OpenAiClient::PolishError, /empty response/)
      end
    end

    context 'when GPT returns invalid JSON' do
      before do
        allow(mock_client).to receive(:chat).and_return({
          'choices' => [{ 'message' => { 'content' => 'not valid json' } }]
        })
      end

      it 'raises PolishError' do
        expect {
          described_class.polish_text_for_pdf(
            notes: notes,
            items_text: items_text,
            locale: locale
          )
        }.to raise_error(OpenAiClient::PolishError, /parse/)
      end
    end

    context 'when GPT returns invalid structure' do
      before do
        allow(mock_client).to receive(:chat).and_return({
          'choices' => [{ 'message' => { 'content' => '{"wrong": "structure"}' } }]
        })
      end

      it 'raises PolishError' do
        expect {
          described_class.polish_text_for_pdf(
            notes: notes,
            items_text: items_text,
            locale: locale
          )
        }.to raise_error(OpenAiClient::PolishError, /invalid structure/)
      end
    end

    context 'when GPT API fails' do
      before do
        allow(mock_client).to receive(:chat).and_raise(StandardError.new('API timeout'))
      end

      it 'raises PolishError with API error message' do
        expect {
          described_class.polish_text_for_pdf(
            notes: notes,
            items_text: items_text,
            locale: locale
          )
        }.to raise_error(OpenAiClient::PolishError, /API timeout/)
      end
    end

    context 'with English locale' do
      let(:locale) { 'en' }
      let(:gpt_response) do
        {
          'choices' => [
            {
              'message' => {
                'content' => JSON.generate({
                  notes: 'Customer wants urgent work.',
                  items: [
                    { index: 0, description: 'Large oak tree' }
                  ]
                })
              }
            }
          ]
        }
      end

      before do
        allow(mock_client).to receive(:chat).and_return(gpt_response)
      end

      it 'includes English in system prompt' do
        expect(mock_client).to receive(:chat) do |params|
          system_message = params[:parameters][:messages].find { |m| m[:role] == 'system' }
          expect(system_message[:content]).to include('English')
          gpt_response
        end

        described_class.polish_text_for_pdf(
          notes: 'test',
          items_text: [{ index: 0, description: 'test' }],
          locale: 'en'
        )
      end
    end

    context 'with Spanish locale' do
      let(:locale) { 'es' }
      let(:gpt_response) do
        {
          'choices' => [
            {
              'message' => {
                'content' => JSON.generate({
                  notes: 'Cliente desea trabajo urgente.',
                  items: [
                    { index: 0, description: 'Árbol de roble grande' }
                  ]
                })
              }
            }
          ]
        }
      end

      before do
        allow(mock_client).to receive(:chat).and_return(gpt_response)
      end

      it 'includes Spanish in system prompt' do
        expect(mock_client).to receive(:chat) do |params|
          system_message = params[:parameters][:messages].find { |m| m[:role] == 'system' }
          expect(system_message[:content]).to include('Spanish')
          gpt_response
        end

        described_class.polish_text_for_pdf(
          notes: 'test',
          items_text: [{ index: 0, description: 'test' }],
          locale: 'es'
        )
      end
    end
  end

  describe '.transcribe_audio' do
    let(:audio_binary) { 'fake audio data' }
    let(:mime_type) { 'audio/webm' }

    context 'when Whisper call succeeds' do
      let(:whisper_response) do
        {
          'text' => 'Hello world',
          'language' => 'en'
        }
      end

      before do
        allow(mock_audio).to receive(:transcribe).and_return(whisper_response)
      end

      it 'returns transcript and language' do
        result = described_class.transcribe_audio(
          audio_binary: audio_binary,
          mime_type: mime_type
        )

        expect(result[:text]).to eq('Hello world')
        expect(result[:language]).to eq('en')
      end
    end

    context 'when Whisper fails' do
      before do
        allow(mock_audio).to receive(:transcribe).and_raise(StandardError.new('Whisper error'))
      end

      it 'raises TranscriptionError' do
        expect {
          described_class.transcribe_audio(
            audio_binary: audio_binary,
            mime_type: mime_type
          )
        }.to raise_error(OpenAiClient::TranscriptionError, /Whisper error/)
      end
    end
  end

  describe '.interpret_voice_instructions' do
    let(:transcript) { 'Add stump grinding for $150' }
    let(:language) { 'en' }
    let(:quote_draft) do
      {
        'status' => 'draft',
        'items' => [],
        'totalPrice' => 0,
        'notes' => ''
      }
    end

    context 'when GPT call succeeds' do
      let(:gpt_response) do
        {
          'choices' => [
            {
              'message' => {
                'content' => JSON.generate({
                  status: 'draft',
                  items: [
                    { itemId: 'NEW_ITEM_1', type: 'stump_grinding', description: 'Stump grinding', price: 15000 }
                  ],
                  totalPrice: 15000,
                  notes: ''
                })
              }
            }
          ]
        }
      end

      before do
        allow(mock_client).to receive(:chat).and_return(gpt_response)
      end

      it 'returns updated quote' do
        result = described_class.interpret_voice_instructions(
          transcript: transcript,
          language: language,
          quote_draft: quote_draft
        )

        expect(result['items'].length).to eq(1)
        expect(result['items'][0]['type']).to eq('stump_grinding')
        expect(result['totalPrice']).to eq(15000)
      end
    end

    context 'when GPT returns invalid JSON' do
      before do
        allow(mock_client).to receive(:chat).and_return({
          'choices' => [{ 'message' => { 'content' => 'invalid json' } }]
        })
      end

      it 'raises InterpretationError' do
        expect {
          described_class.interpret_voice_instructions(
            transcript: transcript,
            language: language,
            quote_draft: quote_draft
          )
        }.to raise_error(OpenAiClient::InterpretationError, /parse/)
      end
    end
  end
end
