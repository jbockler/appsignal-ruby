describe Appsignal::Rack::AbstractMiddleware do
  let(:app) { DummyApp.new }
  let(:env) do
    Rack::MockRequest.env_for(
      "/some/path",
      "REQUEST_METHOD" => "GET",
      :params => { "page" => 2, "query" => "lorem" },
      "rack.session" => { "session" => "data", "user_id" => 123 }
    )
  end
  let(:middleware) { described_class.new(app, options) }

  let(:appsignal_env) { :default }
  let(:options) { {} }
  before { start_agent(:env => appsignal_env) }
  around { |example| keep_transactions { example.run } }

  def make_request
    middleware.call(env)
  end

  def make_request_with_error(error_class, error_message)
    expect { make_request }.to raise_error(error_class, error_message)
  end

  describe "#call" do
    context "when not active" do
      let(:appsignal_env) { :inactive_env }

      it "does not instrument the request" do
        expect { make_request }.to_not(change { created_transactions.count })
      end

      it "calls the next middleware in the stack" do
        make_request
        expect(app).to be_called
      end
    end

    context "when appsignal is active" do
      it "creates a transaction for the request" do
        expect { make_request }.to(change { created_transactions.count }.by(1))

        expect(last_transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
      end

      it "wraps the response body in a BodyWrapper subclass" do
        _status, _headers, body = make_request
        expect(body).to be_kind_of(Appsignal::Rack::BodyWrapper)
      end

      context "without an error" do
        before { make_request }

        it "calls the next middleware in the stack" do
          expect(app).to be_called
        end

        it "does not record an error" do
          expect(last_transaction).to_not have_error
        end

        context "without :instrument_event_name option set" do
          let(:options) { {} }

          it "does not record an instrumentation event" do
            expect(last_transaction).to_not include_event
          end
        end

        context "with :instrument_event_name option set" do
          let(:options) { { :instrument_event_name => "event_name.category" } }

          it "records an instrumentation event" do
            expect(last_transaction).to include_event(:name => "event_name.category")
          end
        end

        it "completes the transaction" do
          expect(last_transaction).to be_completed
          expect(Appsignal::Transaction.current)
            .to be_kind_of(Appsignal::Transaction::NilTransaction)
        end

        context "when instrument_event_name option is nil" do
          let(:options) { { :instrument_event_name => nil } }

          it "does not record an instrumentation event" do
            expect(last_transaction).to_not include_events
          end
        end
      end

      context "with an error" do
        let(:error) { ExampleException.new("error message") }
        let(:app) { lambda { |_env| raise ExampleException, "error message" } }

        it "create a transaction for the request" do
          expect { make_request_with_error(ExampleException, "error message") }
            .to(change { created_transactions.count }.by(1))

          expect(last_transaction).to have_namespace(Appsignal::Transaction::HTTP_REQUEST)
        end

        describe "error" do
          before do
            make_request_with_error(ExampleException, "error message")
          end

          it "records the error" do
            expect(last_transaction).to have_error("ExampleException", "error message")
          end

          it "completes the transaction" do
            expect(last_transaction).to be_completed
            expect(Appsignal::Transaction.current)
              .to be_kind_of(Appsignal::Transaction::NilTransaction)
          end

          context "with :report_errors set to false" do
            let(:app) { lambda { |_env| raise ExampleException, "error message" } }
            let(:options) { { :report_errors => false } }

            it "does not record the exception on the transaction" do
              expect(last_transaction).to_not have_error
            end
          end

          context "with :report_errors set to true" do
            let(:app) { lambda { |_env| raise ExampleException, "error message" } }
            let(:options) { { :report_errors => true } }

            it "records the exception on the transaction" do
              expect(last_transaction).to have_error("ExampleException", "error message")
            end
          end

          context "with :report_errors set to a lambda that returns false" do
            let(:app) { lambda { |_env| raise ExampleException, "error message" } }
            let(:options) { { :report_errors => lambda { |_env| false } } }

            it "does not record the exception on the transaction" do
              expect(last_transaction).to_not have_error
            end
          end

          context "with :report_errors set to a lambda that returns true" do
            let(:app) { lambda { |_env| raise ExampleException, "error message" } }
            let(:options) { { :report_errors => lambda { |_env| true } } }

            it "records the exception on the transaction" do
              expect(last_transaction).to have_error("ExampleException", "error message")
            end
          end
        end
      end

      context "without action name metadata" do
        it "reports no action name" do
          make_request

          expect(last_transaction).to_not have_action
        end
      end

      # Partial duplicate tests from Appsignal::Rack::ApplyRackRequest that
      # ensure the request metadata is set on via the AbstractMiddleware.
      describe "request metadata" do
        it "sets request metadata" do
          env.merge!("PATH_INFO" => "/some/path", "REQUEST_METHOD" => "GET")
          make_request

          expect(last_transaction).to include_metadata(
            "request_method" => "GET",
            "method" => "GET",
            "request_path" => "/some/path",
            "path" => "/some/path"
          )
          expect(last_transaction).to include_environment(
            "REQUEST_METHOD" => "GET",
            "PATH_INFO" => "/some/path"
            # and more, but we don't need to test Rack mock defaults
          )
        end

        it "sets request parameters" do
          make_request

          expect(last_transaction).to include_params(
            "page" => "2",
            "query" => "lorem"
          )
        end

        it "sets session data" do
          make_request

          expect(last_transaction).to include_session_data("session" => "data", "user_id" => 123)
        end

        context "with queue start header" do
          let(:queue_start_time) { fixed_time * 1_000 }

          it "sets the queue start" do
            env["HTTP_X_REQUEST_START"] = "t=#{queue_start_time.to_i}" # in milliseconds
            make_request

            expect(last_transaction).to have_queue_start(queue_start_time)
          end
        end

        class SomeFilteredRequest
          attr_reader :env

          def initialize(env)
            @env = env
          end

          def path
            "/static/path"
          end

          def request_method
            "GET"
          end

          def filtered_params
            { "abc" => "123" }
          end

          def session
            { "data" => "value" }
          end
        end

        context "with overridden request class and params method" do
          let(:options) do
            { :request_class => SomeFilteredRequest, :params_method => :filtered_params }
          end

          it "uses the overridden request class and params method to fetch params" do
            make_request

            expect(last_transaction).to include_params("abc" => "123")
          end

          it "uses the overridden request class to fetch session data" do
            make_request

            expect(last_transaction).to include_session_data("data" => "value")
          end
        end
      end

      context "with parent instrumentation" do
        let(:transaction) { http_request_transaction }
        before do
          env[Appsignal::Rack::APPSIGNAL_TRANSACTION] = transaction
          set_current_transaction(transaction)
        end

        it "uses the existing transaction" do
          make_request

          expect { make_request }.to_not(change { created_transactions.count })
        end

        it "wraps the response body in a BodyWrapper subclass" do
          _status, _headers, body = make_request
          expect(body).to be_kind_of(Appsignal::Rack::BodyWrapper)

          body.to_ary
          response_events =
            last_transaction.to_h["events"].count do |event|
              event["name"] == "process_response_body.rack"
            end
          expect(response_events).to eq(1)
        end

        context "when the response body is already instrumented" do
          let(:body) { Appsignal::Rack::BodyWrapper.wrap(["hello!"], transaction) }
          let(:app) { DummyApp.new { [200, {}, body] } }

          it "doesn't wrap the body again" do
            env[Appsignal::Rack::APPSIGNAL_RESPONSE_INSTRUMENTED] = true
            _status, _headers, body = make_request
            expect(body).to eq(body)

            body.to_ary
            response_events =
              last_transaction.to_h["events"].count do |event|
                event["name"] == "process_response_body.rack"
              end
            expect(response_events).to eq(1)
          end
        end

        context "with error" do
          let(:app) { lambda { |_env| raise ExampleException, "error message" } }

          it "doesn't record the error on the transaction" do
            make_request_with_error(ExampleException, "error message")

            expect(last_transaction).to_not have_error
          end
        end

        it "doesn't complete the existing transaction" do
          make_request

          expect(env[Appsignal::Rack::APPSIGNAL_TRANSACTION]).to_not be_completed
        end

        context "with custom set action name" do
          it "does not overwrite the action name" do
            env[Appsignal::Rack::APPSIGNAL_TRANSACTION].set_action("My custom action")
            env["appsignal.action"] = "POST /my-action"
            make_request

            expect(last_transaction).to have_action("My custom action")
          end
        end

        context "with :report_errors set to false" do
          let(:app) { lambda { |_env| raise ExampleException, "error message" } }
          let(:options) { { :report_errors => false } }

          it "does not record the error on the transaction" do
            make_request_with_error(ExampleException, "error message")

            expect(last_transaction).to_not have_error
          end
        end

        context "with :report_errors set to true" do
          let(:app) { lambda { |_env| raise ExampleException, "error message" } }
          let(:options) { { :report_errors => true } }

          it "records the error on the transaction" do
            make_request_with_error(ExampleException, "error message")

            expect(last_transaction).to have_error("ExampleException", "error message")
          end
        end

        context "with :report_errors set to a lambda that returns false" do
          let(:app) { lambda { |_env| raise ExampleException, "error message" } }
          let(:options) { { :report_errors => lambda { |_env| false } } }

          it "does not record the exception on the transaction" do
            make_request_with_error(ExampleException, "error message")

            expect(last_transaction).to_not have_error
          end
        end

        context "with :report_errors set to a lambda that returns true" do
          let(:app) { lambda { |_env| raise ExampleException, "error message" } }
          let(:options) { { :report_errors => lambda { |_env| true } } }

          it "records the error on the transaction" do
            make_request_with_error(ExampleException, "error message")

            expect(last_transaction).to have_error("ExampleException", "error message")
          end
        end
      end
    end
  end
end
