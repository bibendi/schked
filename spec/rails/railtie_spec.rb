# frozen_string_literal: true

require "rails_helper"

describe Schked::Railtie do
  describe "schked.config" do
    let(:config) { Schked::Config.new }

    before do
      allow(Schked).to receive(:config).and_return(config)
    end

    context "when by default root schedule doesn't exist" do
      it { expect(config.paths).to be_empty }
    end

    context "when a root schedule exists" do
      let(:schedule_path) { Rails.root.join("config/schedule.rb").to_s }
      let(:initializer) { Schked::Railtie::PathsConfig }

      before do
        File.write(schedule_path, "")
      end

      after do
        File.unlink(schedule_path)
        config.paths.delete(schedule_path)
      end

      it "adds to paths" do
        initializer.call(double("app", root: Rails.root))
        expect(config.paths).to match_array([schedule_path])
      end

      context "when path is already added" do
        before { config.paths << schedule_path }

        it "does not add it twice" do
          initializer.call(double("app", root: Rails.root))
          expect(config.paths).to match_array([schedule_path])
        end
      end

      context "when passed do_not_load_root_schedule config option" do
        before { config.do_not_load_root_schedule = true }

        it "doesn't add root schedule to paths" do
          expect(config.paths).to be_empty
        end
      end
    end
  end
end
