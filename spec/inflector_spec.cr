require "spec"
require "../src/active_support_cr"

describe "ActiveSupport::Inflector" do
  it "underscore" do
    "Player".underscore.should eq("player")
    "PlayerInjury".underscore.should eq("player_injury")
    "AdminUser".underscore.should eq("admin_user")
    "HTTPClient".underscore.should eq("http_client")
    "Sidekiq::PipelineNode".underscore.should eq("sidekiq/pipeline_node")
  end

  it "camelize" do
    "player".camelize.should eq("Player")
    "player_injury".camelize.should eq("PlayerInjury")
    "sidekiq/pipeline_node".camelize.should eq("Sidekiq::PipelineNode")
  end

  it "pluralize" do
    "player".pluralize.should eq("players")
    "academy".pluralize.should eq("academies")
    "coach".pluralize.should eq("coaches")
    "match".pluralize.should eq("matches")
    "config".pluralize.should eq("configs")
    "person".pluralize.should eq("people")
    "information".pluralize.should eq("information")
    "priority_match".pluralize.should eq("priority_matches")
  end

  it "tableize" do
    "Player".tableize.should eq("players")
    "PlayerInjury".tableize.should eq("player_injuries")
    "AdminUser".tableize.should eq("admin_users")
    "CspConfig".tableize.should eq("csp_configs")
  end
end
