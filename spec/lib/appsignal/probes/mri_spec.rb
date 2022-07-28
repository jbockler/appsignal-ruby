class AppsignalMock
  attr_reader :gauges

  def initialize
    @gauges = []
  end

  def set_gauge(*args) # rubocop:disable Naming/AccessorMethodName
    @gauges << args
  end
end

describe Appsignal::Probes::MriProbe do
  let(:appsignal_mock) { AppsignalMock.new }
  let(:probe) { described_class.new(appsignal_mock) }

  describe ".dependencies_present?" do
    if DependencyHelper.running_jruby? || DependencyHelper.running_ruby_2_0?
      it "should not be present" do
        expect(described_class.dependencies_present?).to be_falsy
      end
    else
      it "should be present" do
        expect(described_class.dependencies_present?).to be_truthy
      end
    end
  end

  unless DependencyHelper.running_jruby? || DependencyHelper.running_ruby_2_0?
    describe "#call" do
      it "should track vm metrics" do
        probe.call
        expect_gauge_value("ruby_vm", :tags => { :metric => :class_serial })
        expect_gauge_value("ruby_vm", :tags => { :metric => :global_constant_state })
      end

      it "tracks thread counts" do
        probe.call
        expect_gauge_value("thread_count")
      end

      it "tracks GC total time" do
        probe.call
        expect_gauge_value("gc_total_time")
      end

      it "tracks GC run count" do
        expect(GC).to receive(:count).and_return(10, 15)
        expect(GC).to receive(:stat).and_return(
          { :minor_gc_count => 10, :major_gc_count => 10 },
          :minor_gc_count => 16, :major_gc_count => 17
        )
        probe.call
        probe.call
        expect_gauge_value("gc_count", 5, :tags => { :metric => :gc_count })
        expect_gauge_value("gc_count", 6, :tags => { :metric => :minor_gc_count })
        expect_gauge_value("gc_count", 7, :tags => { :metric => :major_gc_count })
      end

      it "tracks object allocation" do
        expect(GC).to receive(:stat).and_return(
          { :total_allocated_objects => 10 },
          :total_allocated_objects => 15
        )
        # Only tracks delta value so the needs to be called twice
        probe.call
        probe.call
        expect_gauge_value("allocated_objects", 5)
      end

      it "tracks heap slots" do
        probe.call
        expect_gauge_value("heap_slots", :tags => { :metric => :heap_live })
        expect_gauge_value("heap_slots", :tags => { :metric => :heap_free })
      end
    end
  end

  def expect_gauge_value(expected_key, expected_value = nil, tags: nil)
    expected_tags = tags
    expect(appsignal_mock.gauges).to satisfy do |gauges|
      gauges.any? do |distribution_value|
        key, value, tags = distribution_value
        next unless key == expected_key
        next unless expected_value ? expected_value == value : !value.nil?
        next if tags && tags != expected_tags

        true
      end
    end
  end
end
