# encoding: utf-8

require "helpers/aws_helper"
require "helpers/email_helper"
require "models/source_model"

class RecordingController < Adhearsion::CallController
  include AwsHelper
  include EmailHelper

  def run
    logger.info "Recording requested"
    extract_metadata
    play_audio "file:///usr/share/assets/beep.mp3" # This file is on the FreeSWITCH server
    record async: true, format: 'mp3' do |event|
      # The following is exectuted to process the recording once it has stopped
      recording = Source.new(event.recording.uri)
      bucket = ENV["AWS_RECORDINGS_BUCKET_DEV"]
      bucket = ENV["AWS_RECORDINGS_BUCKET_PROD"] if Adhearsion.config.platform.environment == :production

      @recording_metadata[:end_time] = Time.now

      if recording.pathname.nil?
        message = "No path extracted from the recording: #{event.recording}"
        logger.warn message
        raise message
      end

      public_url = AwsHelper.upload_to_s3(recording.pathname, bucket)
      logger.info "Recording saved at #{public_url}"

      recording.delete unless public_url.empty?
      logger.warn "Couldn't save recording to S3, the file has been kept at #{recording.pathname}" if public_url.empty?

      EmailHelper.send_email public_url, @recording_metadata
    end
  end

  def extract_metadata
    sip_regex = /^sip:(.+)@.*$/i
    @recording_metadata = {
      from:       call.from.match(sip_regex)[1],
      to:         call.to.match(sip_regex)[1],
      start_time: Time.now
    }
  end
end
