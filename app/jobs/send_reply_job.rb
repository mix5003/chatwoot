class SendReplyJob < ApplicationJob
  queue_as :high

  def perform(message_id, conversation_id)
    conversation = Conversation.lock.find(conversation_id)
    message = Message.find(message_id)

    next_message_that_should_be_send = conversation.messages.where(
      message_type: :outgoing,
      status: [:sent, nil],
    ).first

    if next_message_that_should_be_send != nil and message.id != next_message_that_should_be_send.id
      sleep(0.1)
      ::SendReplyJob.perform_later(message_id, message.conversation_id)
      return
    end

    channel_name = conversation.inbox.channel.class.to_s

    services = {
      'Channel::TwitterProfile' => ::Twitter::SendOnTwitterService,
      'Channel::TwilioSms' => ::Twilio::SendOnTwilioService,
      'Channel::Line' => ::Line::SendOnLineService,
      'Channel::Telegram' => ::Telegram::SendOnTelegramService,
      'Channel::Whatsapp' => ::Whatsapp::SendOnWhatsappService,
      'Channel::Sms' => ::Sms::SendOnSmsService,
      'Channel::Instagram' => ::Instagram::SendOnInstagramService
    }

    case channel_name
    when 'Channel::FacebookPage'
      send_on_facebook_page(message)
    else
      services[channel_name].new(message: message).perform if services[channel_name].present?
    end
  end

  private

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
