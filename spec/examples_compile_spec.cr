require "./spec_helper"

# This spec verifies that example files can be type-checked by the Crystal compiler
# by shelling out to `crystal build --no-codegen`.
describe "Examples" do
  {% for name in ["minimal", "echo", "announce", "broadcast"] %}
    it "{{name.id}}.cr compiles without errors" do
      result = Process.run(
        "crystal",
        ["build", "examples/{{name.id}}.cr", "--no-codegen"],
        chdir: File.join(__DIR__, ".."),
        output: output = IO::Memory.new,
        error: error = IO::Memory.new
      )
      unless result.success?
        fail "examples/{{name.id}}.cr failed to compile:\n#{error.to_s}\n#{output.to_s}"
      end
    end
  {% end %}
end
