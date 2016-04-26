# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.  Use
# of this source code is governed by a BSD-style license, found in the LICENSE
# file.

require 'sys/filesystem'
include Sys

module Blockbridge
  class VolumeMonitor
    include Helpers
    attr_reader :config
    attr_reader :logger
    attr_reader :status
    attr_reader :cache_version

    def self.cache
      @@cache
    end

    def initialize(address, port, config, status, logger)
      @config = config
      @logger = logger
      @status = status
      @@cache = self
    end

    def monitor_interval_s
      ENV['BLOCKBRIDGE_MONITOR_INTERVAL_S'] || 10
    end

    def run
      EM::Synchrony.run_and_add_periodic_timer(monitor_interval_s, &method(:volume_monitor))
    end

    def reset
      @cache_version = nil
    end

    def volume_invalidate(name)
      logger.info "#{name} removing stale volume from docker"
      vol_cache_enable(name)
      defer do
        docker_volume_rm(name)
      end
      vol_cache_rm(name)
      logger.info "#{name} cache invalidated."
    rescue => e
      vol_cache_disable(name)
      logger.error "Failed to remove docker cached volume: #{name}: #{e.message}"
    end

    def volume_user_lookup(user)
      raise Blockbridge::Notfound if bbapi.user_profile.list(login: user).length == 0
    end

    def volume_lookup_info(vol)
      volume_user_lookup(vol[:user])
      info = bbapi.xmd.info("docker-volume-#{vol[:name]}")
      info[:data].merge(info[:data][:volume])
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound
    end

    def cache_status_create
      xmd = bbapi.xmd.info(vol_cache_ref) rescue nil
      return xmd unless xmd.nil?
      bbapi.xmd.create(ref: vol_cache_ref)
    rescue Blockbridge::Api::ConflictError
    end

    def cache_version_lookup
      xmd = cache_status_create
      xmd[:seq]
    rescue Excon::Errors::NotFound, Excon::Errors::Gone
    end

    def volume_async_remove(vol, vol_info, vol_env)
      if vol_info
        return unless vol_info[:deleted]
        return unless ((Time.now.tv_sec - vol_info[:deleted]) > monitor_interval_s)
        raise Blockbridge::VolumeInuse if bb_is_attached(vol[:name], vol[:user], vol_info[:scope_token])
        bb_remove(vol[:name], vol[:user], vol_info[:scope_token])
      end
      vol_cache_rm(vol[:name])
      logger.info "#{vol[:name]} async removed"
    rescue Excon::Errors::NotFound, Excon::Errors::Gone, Blockbridge::NotFound
      logger.debug "#{vol[:name]} async remove: volume not found"
    rescue Blockbridge::VolumeInuse
      logger.debug "#{vol[:name]} async remove: not removing; volume still in use"
    rescue Blockbridge::CommandError => e
      logger.debug "#{vol[:name]} async remove: #{e.message}"
      if e.message.include? "not found"
        vol_cache_rm(vol[:name])
      end
      raise
    end

    def volume_cache_check
      new_cache_version = cache_version_lookup
      return unless new_cache_version != cache_version
      logger.info "Validating volume cache"
      revalidate = false
      vol_cache_foreach do |v, vol|
        volume_invalidate(vol[:name]) unless (vol_info = volume_lookup_info(vol))
        revalidate = true if vol[:deleted]
        volume_async_remove(vol, vol_info, vol[:env]) if vol[:deleted]
      end
      @cache_version = new_cache_version unless revalidate
    end

    def volume_host_info_create(vol, vol_info)
      xmd = bbapi(vol[:user], vol_info[:scope_token]).xmd.info(vol_host_ref(vol[:name])) rescue nil
      return xmd unless xmd.nil?
      params = {
        ref: vol_host_ref(vol[:name]),
        #xref: volume_ref_name(vol[:name]),  -- bug, won't let you create more than 1 xmd with same xref
        data: {
          hostinfo: {
            :_schema => "terminal",
            :data    => {
              ongoing: true,
              'css' => {
                'min-height' => '450px',
              },
            },
          },
        },
      }

      bbapi(vol[:user], vol_info[:scope_token]).xmd.create(params)
    rescue Blockbridge::Api::ConflictError
    end

    def disk_attach_host(x)
      host = x[:data][:attach][:data][:host]
    end

    def disk_attach_mode(x)
      return x[:mode] if x[:mode]
      return x[:data][:attach][:data][:mode] if x[:data]
    rescue
      return 'unknown'
    end

    def disk_attach_mode_str(x)
      mode = disk_attach_mode(x)
      case mode
      when 'wo'
        'write-only'
      when 'rw'
        'read-write'
      when 'ro'
        'read-only'
      else
        'unknown'
      end
    end

    def volume_options_include
      [
        :capacity,
        :iops,
        :attributes,
        :clone_basis,
        :type,
      ]
    end

    def volume_host_info_get(vol, vol_info)
      unless (xmd = bb_is_attached(vol[:name], vol[:user], vol_info[:scope_token]).first rescue nil)
        return [ "Not attached." ]
      end

      info = [
        "Docker volume      #{vol[:name]}",
        "Attached to        #{disk_attach_host(xmd)}",
        "Mode               #{disk_attach_mode_str(xmd)}",
        "Transport          #{xmd.data.attach.data.secure ? "#{xmd.data.attach.data.secure}" : 'TCP/IP'}",
      ]

      volume_options_include.each do |k|
        info.push "#{k.to_s.downcase.capitalize.ljust(18)} #{vol_info[k]}" if vol_info[k]
      end

      cmd = ['/bb/bin/nsexec', '/ns-mnt/mnt', 'df', '-kTh', mnt_path(vol[:name])]
      res = cmd_exec_raw(*cmd, {})

      res.each_line do |l|
        next if l =~ /Filesystem/
        md = /^(?<filesystem>.*?)\s+(?<type>.*?)\s+(?<size>.*?)\s+(?<used>.*?)\s+(?<avail>.*?)\s+(?<use_percent>.*?)\s+(?<mounted>.*)/.match(l)
        next unless md
        fsinfo = [
          "Filesystem         #{md[:filesystem]}",
          "Type               #{md[:type]}",
          "Size               #{md[:size]}",
          "Used               #{md[:used]}",
          "Available          #{md[:avail]}",
          "Used%              #{md[:use_percent]}",
          "Mounted on         #{md[:mounted]}",
        ]
        info.push ""
        info.concat fsinfo
      end

      params = {
        all: true,
        filters: {
          volume: [ vol[:name] ],
        }.to_json
      }

      defer do
        Docker::Container.all(params).each do |c|
          cinfo = [
            "Container ID       #{c.id[0..12]}",
            "Name               #{c.info['Names'].first[1..100]}",
            "Image              #{c.info['Image']}",
            "Command            #{c.info['Command']}",
            "State              #{c.info['State']}",
            "Status             #{c.info['Status']}",
          ]

          info.push ""
          info.concat cinfo

          c.info['Mounts'].each do |m|
            next unless m['Name'] == vol[:name]
            minfo = [
              "Container mount    #{m['Destination']}",
              "Propagation        #{m['Propagation']}",
            ]

            info.push ""
            info.concat minfo
          end
        end
      end

      info.push ""
      info
    end

    def volume_host_info_update(vol, vol_info)
      params = {
        mode: 'patch',
        data: [ { op: 'add', path: '/hostinfo/data/lines',
                  value: volume_host_info_get(vol, vol_info) } ]
      }
      bbapi(vol[:user], vol_info[:scope_token]).xmd.update(vol_host_ref(vol[:name]), params)
    end

    def volume_host_info
      vol_cache_foreach  do |v, vol|
        next unless (vol_info = volume_lookup_info(vol))
        next unless (xmd = bb_is_attached(vol[:name], vol[:user], vol_info[:scope_token]))
        next unless disk_attach_host(xmd.first) == ENV['HOSTNAME']
        volume_host_info_create(vol, vol_info)
        volume_host_info_update(vol, vol_info)
      end
    end

    def volume_monitor
      volume_cache_check
      volume_host_info
    rescue => e
      msg = e.message.chomp.squeeze("\n")
      msg.each_line do |m| logger.error "monitor: #{m.chomp}" end
      e.backtrace.each do |b| logger.error(b) end
    end
  end
end
