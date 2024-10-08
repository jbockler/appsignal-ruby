module EnvHelpers
  def http_request_env_with_data(args = {})
    with_queue_start = args.delete(:with_queue_start)
    path = args.delete(:path) || "/blog"
    request = Rack::MockRequest.env_for(
      path,
      :params => args[:params] || {
        "controller" => "blog_posts",
        "action" => "show",
        "id" => "1"
      }
    ).merge(
      :controller => "BlogPostsController",
      :action => "show",
      :request_format => "html",
      :request_method => "GET",
      :status => "200",
      :view_runtime => 500,
      :db_runtime => 500,
      :metadata => { :key => "value" }
    ).merge(args)

    # Set default queue value
    if with_queue_start
      request["HTTP_X_QUEUE_START"] = "t=#{(fixed_time * 1_000).to_i}" # in milliseconds
    end

    request
  end

  def background_env_with_data(args = {})
    {
      :class => "BackgroundJob",
      :method => "perform",
      :priority => 1,
      :attempts => 0,
      :queue => "default",
      :queue_start => fixed_time
    }.merge(args)
  end

  def set_rails_session_data(request, data)
    ActionDispatch::Request::Session.create(
      rails_session_store(data),
      request,
      {}
    )
  end

  def rails_session_store(data)
    Class.new do
      def initialize(data)
        @data = data
      end

      def load_session(_env)
        [1, @data]
      end

      def session_exists?(_env)
        true
      end

      def delete_session(_env, _id, _options)
        123
      end
    end.new(data)
  end
end
