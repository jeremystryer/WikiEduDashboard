# frozen_string_literal: true

require_dependency "#{Rails.root}/lib/data_cycle/batch_update_logging"
require_dependency "#{Rails.root}/lib/surveys/survey_notifications_manager"

class SurveyUpdate
  include BatchUpdateLogging

  def initialize
    setup_logger
    return if updates_paused?

    run_update_with_pid_files(:survey)
  end

  private

  def run_update
    log_start_of_update 'Survey update starting.'
    create_survey_notifications
    send_survey_notifications
    send_survey_notification_follow_ups
    log_end_of_update 'Survey update finished.'
  end

  def create_survey_notifications
    log_message 'Creating new SurveyNotifications'
    before_count = SurveyNotification.count
    SurveyNotificationsManager.create_notifications
    after_count = SurveyNotification.count
    log_message "#{after_count - before_count} SurveyNotifications created"
  end

  def send_survey_notifications
    log_message 'Sending survey invitation emails'
    before_count = SurveyNotification.where.not(email_sent_at: nil).count
    try_to_process_notifications(:send_email)
    after_count = SurveyNotification.where.not(email_sent_at: nil).count
    log_message "#{after_count - before_count} survey invitations sent"
  end

  def send_survey_notification_follow_ups
    log_message 'Sending survey reminder emails'
    before_count = SurveyNotification.sum(:follow_up_count)
    try_to_process_notifications(:send_follow_up)
    after_count = SurveyNotification.sum(:follow_up_count)
    log_message "#{after_count - before_count} survey reminders sent"
  end

  def try_to_process_notifications(method)
    SurveyNotification.active.each do |notification|
      @notification = notification
      # Sending an email and updating the record returns true.
      # When no email needs to be sent, the email methods return nil.
      next unless notification.send(method)
      # Don't send emails too quickly, to avoid being throttled.
      # This may no longer be necessary since we swithced to Mailgun.
      sleep 2 unless Rails.env.test?
    end
  rescue Mailgun::CommunicationError => e
    log_message "Error emailing for SurveyNotification #{@notification.id}"
    log_end_of_update 'Survey update errored'
    raise e
  end
end
