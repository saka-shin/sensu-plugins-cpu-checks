#! /usr/bin/env ruby
#
#   check-cpu
#
# DESCRIPTION:
#   Check cpu usage
#
# OUTPUT:
#   plain text
#
# PLATFORMS:
#   Linux
#
# DEPENDENCIES:
#   gem: sensu-plugin
#
# USAGE:
#   #YELLOW
#
# NOTES:
#
# LICENSE:
#   Copyright 2014 Sonian, Inc. and contributors. <support@sensuapp.org>
#   Released under the same terms as Sensu (the MIT license); see LICENSE
#   for details.
#

require 'sensu-plugin/check/cli'

#
# Check CPU
#
class CheckCPU < Sensu::Plugin::Check::CLI
  CPU_METRICS = [:user, :nice, :system, :idle, :iowait, :irq, :softirq, :steal, :guest, :guest_nice].freeze

  option :warn,
         short: '-w WARN',
         proc: proc(&:to_f),
         default: 80

  option :crit,
         short: '-c CRIT',
         proc: proc(&:to_f),
         default: 100

  option :sleep,
         long: '--sleep SLEEP',
         proc: proc(&:to_f),
         default: 1

  option :idle_metrics,
         long: '--idle-metrics METRICS',
         description: 'Treat the specified metrics as idle. Defaults to idle,iowait,steal,guest,guest_nice',
         proc: proc { |x| x.split(/,/).map { |y| y.strip.to_sym } },
         default: [:idle, :iowait, :steal, :guest, :guest_nice]

  option :occurence,
         short: '-o OCCURENCE',
         description: 'Number of consecutive crit/warn',
         proc: proc(&:to_i),
         default: 1

  CPU_METRICS.each do |metric|
    option metric,
           long: "--#{metric}",
           description: "Check cpu #{metric} instead of total cpu usage",
           boolean: true,
           default: false
  end

  def acquire_cpu_stats
    File.open('/proc/stat', 'r').each_line do |line|
      info = line.split(/\s+/)
      name = info.shift
      return info.map(&:to_f) if name =~ /^cpu$/
    end
  end

  def run
    (1..config[:occurence]).each do |occ|
      cpu_stats_before = acquire_cpu_stats
      sleep config[:sleep]
      cpu_stats_after = acquire_cpu_stats

      # Some kernels don't have 'guest' and 'guest_nice' values
      metrics = CPU_METRICS.slice(0, cpu_stats_after.length)

      cpu_total_diff = 0.to_f
      cpu_stats_diff = []
      metrics.each_index do |i|
        cpu_stats_diff[i] = cpu_stats_after[i] - cpu_stats_before[i]
        cpu_total_diff += cpu_stats_diff[i]
      end

      cpu_stats = []
      metrics.each_index do |i|
        cpu_stats[i] = 100 * (cpu_stats_diff[i] / cpu_total_diff)
      end

      idle_diff = metrics.each_with_index.map { |metric, i| config[:idle_metrics].include?(metric) ? cpu_stats_diff[i] : 0.0 }.reduce(0.0, :+)

      cpu_usage = 100 * (cpu_total_diff - idle_diff) / cpu_total_diff
      checked_usage = cpu_usage

      self.class.check_name 'CheckCPU TOTAL'
      metrics.each do |metric|
        if config[metric]
          self.class.check_name "CheckCPU #{metric.to_s.upcase}"
          checked_usage = cpu_stats[metrics.find_index(metric)]
        end
      end

      msg = "total=#{(cpu_usage * 100).round / 100.0}"
      cpu_stats.each_index { |i| msg += " #{metrics[i]}=#{(cpu_stats[i] * 100).round / 100.0}" }
      msg += " occurence=#{occ}"

      message msg

      return ok if checked_usage < config[:crit] && checked_usage < config[:warn]
      return critical if occ == config[:occurence] && checked_usage >= config[:crit]
      return warning if occ == config[:occurence] && checked_usage >= config[:warn]
    end
  end
end
