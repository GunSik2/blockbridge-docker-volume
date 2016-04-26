# Copyright (c) 2015-2016, Blockbridge Networks LLC.  All rights reserved.  Use
# of this source code is governed by a BSD-style license, found in the LICENSE
# file.

module Blockbridge
  class VolumeHostinfo
    include Helpers
    attr_reader :config
    attr_reader :logger
    attr_reader :status

    def self.cache
      @@hostinfo_cache ||= {}
    end

    def initialize(address, port, config, status, logger)
      @config = config
      @logger = logger
      @status = status
    end

    def monitor_interval_s
      ENV['BLOCKBRIDGE_HOSTINFO_INTERVAL_S'] || 10
    end

    def run
      EM::Synchrony.run_and_add_periodic_timer(monitor_interval_s, &method(:volume_hostinfo_run))
    end

    def volume_host_info_lookup(vol, vol_info)
      xmd = bbapi(vol[:user], vol_info[:scope_token]).xmd.info(vol_host_ref(vol[:name])) rescue nil
      return xmd unless xmd.nil?
    end

    def volume_host_info_create(vol, vol_info)
      return if volume_host_info_lookup(vol, vol_info)

      params = {
        ref: vol_host_ref(vol[:name]),
        xref: volume_ref_name(vol[:name]),
        data: {
          hostinfo: {
            :_schema => "terminal",
            :data    => {
              ongoing: false,
              css: {
                'min-height' => '25px',
              },
              lines: [
                "Not Attached.",
              ],
            },
          },
        },
      }
      bbapi(vol[:user], vol_info[:scope_token]).xmd.create(params)
    rescue Blockbridge::Api::ConflictError
    end

    def disk_attach_host(x)
      x[:data][:attach][:data][:host]
    end

    def disk_attach_mode(x)
      return x[:mode] if x[:mode]
      x[:data][:attach][:data][:mode]
    rescue
      'unknown'
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

    def disk_attach_transport_str(x)
      return 'TCP/IP' unless x.data.attach.data.secure
      x.data.attach.data.secure
    rescue
      'TCP/IP'
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

    def volume_host_info_build_volume(vol, vol_info, vol_xmd)
      # top-level volume
      info = [
        "Docker volume      #{vol[:name]}",
      ]

      # volume attachment
      if vol_xmd
        info.concat [
          "Attached to        #{disk_attach_host(vol_xmd)}",
          "Mode               #{disk_attach_mode_str(vol_xmd)}",
          "Transport          #{disk_attach_transport_str(vol_xmd)}",
        ]
      else
        info.concat [
          "Attached to        -Not Attached-"
        ]
      end

      # volume options
      volume_options_include.each do |k|
        info.push "#{k.to_s.downcase.capitalize.ljust(18)} #{vol_info[k]}" if vol_info[k]
      end

      info
    end

    def volume_host_info_build_fs(vol, vol_info, vol_xmd)
      return [] unless vol_xmd
      info = []
      cmd = ['/bb/bin/nsexec', '/ns-mnt/mnt', 'df', '-kTh', mnt_path(vol[:name])]
      res = cmd_exec_raw(*cmd, {})

      res.each_line do |l|
        next if l =~ /Filesystem/
        md = /^(?<filesystem>.*?)\s+(?<type>.*?)\s+(?<size>.*?)\s+(?<used>.*?)\s+(?<avail>.*?)\s+(?<use_percent>.*?)\s+(?<mounted>.*)/.match(l)
        next unless md && md[:mounted] == mnt_path(vol[:name])
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
      info
    rescue Blockbridge::CommandError
      []
    end

    def container_mounts_volume?(c, vol)
      c.info['Mounts'].each do |m|
        return true if m['Source'] == mnt_path(vol[:name])
      end
      false
    end

    def volume_host_info_build_docker(vol, vol_info)
      info = []
      defer do
        params = {
          all: true,
        }
        Docker::Container.all(params).each do |c|
          next unless container_mounts_volume?(c, vol)

          cinfo = [
            "Container ID       #{c.id[0..12]}",
            "Name               #{c.info['Names'].first[1..100]}",
            "Host               #{ENV['HOSTNAME']}",
            "Image              #{c.info['Image']}",
            "Command            #{c.info['Command']}",
            "State              #{c.info['State']}",
            "Status             #{c.info['Status']}",
          ]

          info.push ""
          info.concat cinfo

          c.info['Mounts'].each do |m|
            next unless m['Source'] == mnt_path(vol[:name])
            minfo = [
              "Mount Propagation  #{m['Propagation']}",
              "Mounted on         #{m['Destination']}",
            ]

            info.concat minfo
          end
        end
      end

      info.push ""
      info
    end

    def volume_host_info_build(vol, vol_info, vol_xmd = nil)
      info = []
      info.concat volume_host_info_build_volume(vol, vol_info, vol_xmd)
      info.concat volume_host_info_build_fs(vol, vol_info, vol_xmd)
      info.concat volume_host_info_build_docker(vol, vol_info)

      return if VolumeHostinfo.cache[vol[:name]] == info
      VolumeHostinfo.cache[vol[:name]] = info
    end

    def volume_host_info_display_height(hostinfo)
      return "25px" unless hostinfo.length > 0
      length = hostinfo.length * 18 
      "#{(450..length).min || length}px"
    end

    def volume_host_info_update(vol, vol_info)
      volume_host_info_create(vol, vol_info)
      xmd = bb_get_attached(vol[:name], vol[:user], vol_info[:scope_token])
      if xmd && (vol_xmd = xmd.first)
        # attached
        return unless disk_attach_host(vol_xmd) == ENV['HOSTNAME']
      else
        # detached
        xmd = volume_host_info_lookup(vol, vol_info)
        return unless (xmd.data.hostinfo.data.host.nil? ||
                       (xmd.data.hostinfo.data.host == ENV['HOSTNAME']))
      end

      # build failed ; or no update required
      return unless (hostinfo = volume_host_info_build(vol, vol_info, vol_xmd))

      # push a hostinfo update
      params = {
        mode: 'patch',
        data: [ { op: 'add', path: '/hostinfo/data/lines',
                  value: hostinfo },
                { op: 'add', path: '/hostinfo/data/host',
                  value: ENV['HOSTNAME'] },
                { op: 'add', path: '/hostinfo/data/ongoing',
                  value: vol_xmd ? true : false },
                { op: 'add', path: '/hostinfo/data/css',
                  value: { 'min-height' => "#{volume_host_info_display_height(hostinfo)}" } } ]
      }
      bbapi(vol[:user], vol_info[:scope_token]).xmd.update(vol_host_ref(vol[:name]), params)
    end

    def volume_hostinfo
      vol_cache_foreach do |v, vol|
        next unless (vol_info = bb_lookup_vol_info(vol))
        volume_host_info_update(vol, vol_info)
      end
    end

    def volume_hostinfo_run
      volume_hostinfo
    rescue => e
      msg = e.message.chomp.squeeze("\n")
      msg.each_line do |m| logger.error "hostinfo: #{m.chomp}" end
      e.backtrace.each do |b| logger.error(b) end
    end
  end
end
