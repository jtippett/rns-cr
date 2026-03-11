require "spec"
ENV["RNS_TEST_DISABLE_AUTO_INTERFACE_NETWORK"] = "1"
require "../src/rns"

# Expose Spec::CLI#tags so we can check whether the user requested specific tags.
class Spec::CLI
  def tags
    @tags
  end
end

# By default, skip tagged tests (e.g. "network") and run only unit tests.
# To run network tests: crystal spec --tag network
Spec.around_each do |example|
  tags = Spec.cli.tags
  # When no tags requested, skip any test that has tags
  next if (tags.nil? || tags.empty?) && !example.example.all_tags.empty?
  example.run
end

# Safety net: tear down any interfaces still online after each test, then
# reset Transport state to prevent resource leaks between tests.
Spec.after_each do
  RNS::Transport.interface_objects.each do |iface|
    begin
      iface.teardown if iface.online
    rescue ex
      # Best-effort cleanup — don't fail the next test because of teardown errors
    end
  end
  RNS::Transport.stop_job_loop
  RNS::Transport.reset
end
