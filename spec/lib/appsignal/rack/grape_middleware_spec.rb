if DependencyHelper.grape_present?
  require "appsignal/rack/grape_middleware"

  describe Appsignal::Rack::GrapeMiddleware do
    let(:app) do
      Class.new(::Grape::API) do
        format :json
        post :ping do
          { :message => "Hello world!" }
        end
      end
    end
    let(:api_endpoint) { app.endpoints.first }
    let(:env) do
      http_request_env_with_data \
        "api.endpoint" => api_endpoint,
        "REQUEST_METHOD" => "POST",
        :path => "/ping"
    end
    let(:middleware) { Appsignal::Rack::GrapeMiddleware.new(api_endpoint) }
    let(:transaction) { http_request_transaction }
    before do
      stub_const("GrapeExample::Api", app)
      start_agent
    end
    around do |example|
      keep_transactions { example.run }
    end

    def make_request(env)
      middleware.call(env)
    end

    def make_request_with_exception(env, exception_class, exception_message)
      expect do
        middleware.call(env)
      end.to raise_error(exception_class, exception_message)
    end

    context "with error" do
      let(:app) do
        Class.new(::Grape::API) do
          format :json
          post :ping do
            raise ExampleException, "error message"
          end
        end
      end

      it "sets the error" do
        make_request_with_exception(env, ExampleException, "error message")

        expect(last_transaction).to have_error("ExampleException", "error message")
      end

      context "with env['grape.skip_appsignal_error'] = true" do
        let(:app) do
          Class.new(::Grape::API) do
            format :json
            post :ping do
              env["grape.skip_appsignal_error"] = true
              raise ExampleException, "error message"
            end
          end
        end

        it "does not add the error" do
          make_request_with_exception(env, ExampleException, "error message")

          expect(last_transaction).to_not have_error
        end
      end
    end

    context "with route" do
      let(:app) do
        Class.new(::Grape::API) do
          route([:get, :post], "hello") do
            "Hello!"
          end
        end
      end
      let(:env) do
        http_request_env_with_data \
          "api.endpoint" => api_endpoint,
          "REQUEST_METHOD" => "GET",
          :path => ""
      end

      it "sets non-unique route path" do
        make_request(env)

        expect(last_transaction).to have_action("GET::GrapeExample::Api#/hello")
        expect(last_transaction).to include_metadata("path" => "/hello", "method" => "GET")
      end
    end

    context "with route_param" do
      let(:app) do
        Class.new(::Grape::API) do
          format :json
          resource :users do
            route_param :id do
              get do
                { :name => "Tom" }
              end
            end
          end
        end
      end
      let(:env) do
        http_request_env_with_data \
          "api.endpoint" => api_endpoint,
          "REQUEST_METHOD" => "GET",
          :path => ""
      end

      it "sets non-unique route_param path" do
        make_request(env)

        expect(last_transaction).to have_action("GET::GrapeExample::Api#/users/:id/")
        expect(last_transaction).to include_metadata("path" => "/users/:id/", "method" => "GET")
      end
    end

    context "with namespaced path" do
      context "with symbols" do
        let(:app) do
          Class.new(::Grape::API) do
            format :json
            namespace :v1 do
              namespace :beta do
                post :ping do
                  { :message => "Hello namespaced world!" }
                end
              end
            end
          end
        end

        it "sets namespaced path" do
          make_request(env)

          expect(last_transaction).to have_action("POST::GrapeExample::Api#/v1/beta/ping")
          expect(last_transaction).to include_metadata("path" => "/v1/beta/ping",
            "method" => "POST")
        end
      end

      context "with strings" do
        context "without / prefix" do
          let(:app) do
            Class.new(::Grape::API) do
              format :json
              namespace "v1" do
                namespace "beta" do
                  post "ping" do
                    { :message => "Hello namespaced world!" }
                  end
                end
              end
            end
          end

          it "sets namespaced path" do
            make_request(env)

            expect(last_transaction).to have_action("POST::GrapeExample::Api#/v1/beta/ping")
            expect(last_transaction).to include_metadata(
              "path" => "/v1/beta/ping",
              "method" => "POST"
            )
          end
        end

        context "with / prefix" do
          let(:app) do
            Class.new(::Grape::API) do
              format :json
              namespace "/v1" do
                namespace "/beta" do
                  post "/ping" do
                    { :message => "Hello namespaced world!" }
                  end
                end
              end
            end
          end

          it "sets namespaced path" do
            make_request(env)

            expect(last_transaction).to have_action("POST::GrapeExample::Api#/v1/beta/ping")
            expect(last_transaction).to include_metadata("path" => "/v1/beta/ping",
              "method" => "POST")
          end
        end
      end
    end
  end
end
