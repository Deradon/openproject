#-- encoding: UTF-8

#-- copyright
# OpenProject is an open source project management software.
# Copyright (C) 2012-2021 the OpenProject GmbH
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2013 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See docs/COPYRIGHT.rdoc for more details.
#++
require 'spec_helper'

describe Notifications::JournalWpMailService, with_settings: { journal_aggregation_time_minutes: 0 } do
  let(:project) { FactoryBot.create(:project_with_types) }
  let(:role) { FactoryBot.create(:role, permissions: [:view_work_packages]) }
  let(:author) do
    FactoryBot.create(:user,
                     mail_notification: 'none',
                     member_in_project: project,
                     member_through_role: role)
  end
  let(:recipient) do
    FactoryBot.create(:user,
                      member_in_project: project,
                      member_through_role: role,
                      login: "johndoe")
  end
  let(:work_package) do
    FactoryBot.create(:work_package,
                      project: project,
                      author: author,
                      assigned_to: recipient,
                      type: project.types.first)
  end
  let(:journal) { journal_1 }
  let(:journal_1) { work_package.journals.first }
  let(:journal_2_with_notes) do
    work_package.add_journal author, 'something I have to say'
    work_package.save(validate: false)
    work_package.journals.last
  end
  let(:journal_2_with_status) do
    work_package.status = FactoryBot.create(:status)
    work_package.save(validate: false)
    work_package.journals.last
  end
  let(:journal_2_with_priority) do
    work_package.priority = FactoryBot.create(:priority)
    work_package.save(validate: false)
    work_package.journals.last
  end
  let(:send_mails) { true }
  let(:notification_setting) do
    %w(work_package_added work_package_updated work_package_note_added status_updated work_package_priority_updated)
  end

  def call
    described_class.call(journal, send_mails)
  end

  before do
    # make sure no other calls are made due to WP creation/update
    allow(OpenProject::Notifications).to receive(:send) # ... and do nothing

    login_as(author)
    allow(Setting).to receive(:notified_events).and_return(notification_setting)
  end

  shared_examples_for 'sends mail' do
    let(:sender) { author }

    it 'sends a mail' do
      expect { call }
        .to enqueue_job(Mails::WorkPackageJob)
        .with(journal.id, recipient.id, sender.id)
    end
  end

  shared_examples_for 'sends no mail' do
    it 'sends no mail' do
      expect { call }.to_not enqueue_job(Mails::WorkPackageJob)
      call
    end
  end

  it_behaves_like 'sends mail'

  context 'assignee is placeholder user' do
    let(:recipient) { FactoryBot.create :placeholder_user }

    it_behaves_like 'sends no mail'
  end

  context 'responsible is placeholder user' do
    let(:recipient) { FactoryBot.create :placeholder_user }
    let(:work_package) do
      FactoryBot.create(:work_package,
                        project: project,
                        author: author,
                        responsible: recipient,
                        type: project.types.first)
    end

    it_behaves_like 'sends no mail'
  end

  context 'notification for work_package_added disabled' do
    let(:notification_setting) { %w(work_package_updated work_package_note_added) }

    it_behaves_like 'sends no mail'
  end

  context 'if the journal has a note' do
    let(:journal) { journal_2_with_notes }

    context 'notification for work_package_updated and work_package_note_added disabled' do
      let(:notification_setting) { %w(work_package_added status_updated work_package_priority_updated) }

      it_behaves_like 'sends no mail'
    end

    context 'notification for work_package_updated enabled' do
      let(:notification_setting) { %w(work_package_updated) }

      it_behaves_like 'sends mail'
    end

    context 'notification for work_package_note_added enabled' do
      let(:notification_setting) { %w(work_package_note_added) }

      it_behaves_like 'sends mail'
    end
  end

  context 'if the journal has status update' do
    let(:journal) { journal_2_with_status }

    context 'notification for work_package_updated and status_updated disabled' do
      let(:notification_setting) { %w(work_package_added work_package_note_added work_package_priority_updated) }

      it_behaves_like 'sends no mail'
    end

    context 'notification for work_package_updated enabled' do
      let(:notification_setting) { %w(work_package_updated) }

      it_behaves_like 'sends mail'
    end

    context 'notification for status_updated enabled' do
      let(:notification_setting) { %w(status_updated) }

      it_behaves_like 'sends mail'
    end
  end

  context 'if the journal has priority' do
    let(:journal) { journal_2_with_priority }

    context 'notification for work_package_updated and work_package_priority_updated disabled' do
      let(:notification_setting) { %w(work_package_added work_package_note_added status_updated) }

      it_behaves_like 'sends no mail'
    end

    context 'notification for work_package_updated enabled' do
      let(:notification_setting) { %w(work_package_updated) }

      it_behaves_like 'sends mail'
    end

    context 'notification for work_package_priority_updated enabled' do
      let(:notification_setting) { %w(work_package_priority_updated) }

      it_behaves_like 'sends mail'
    end
  end

  context 'if the author has been deleted' do
    let!(:deleted_user) { DeletedUser.first }

    before do
      work_package
      author.destroy
    end

    it_behaves_like 'sends mail' do
      let(:sender) { deleted_user }
    end
  end

  context 'user is mentioned' do
    let(:work_package) do
      FactoryBot.create(:work_package,
                        project: project,
                        author: author,
                        type: project.types.first)
    end
    let(:recipient) do
      FactoryBot.create(:user,
                        mail_notification: 'only_assigned',
                        member_in_project: project,
                        member_through_role: role,
                        login: "johndoe")
    end

    shared_examples_for 'group mention' do
      context 'group member is allowed to view the work package' do
        context 'user wants to receive notifications' do
          it_behaves_like 'sends mail'
        end

        context 'user disabled notifications' do
          let(:recipient) { FactoryBot.create(:user, mail_notification: User::USER_MAIL_OPTION_NON.first) }

          it_behaves_like 'sends no mail'
        end
      end

      context 'group is not allowed to view the work package' do
        let(:role) { FactoryBot.create(:role, permissions: []) }

        it_behaves_like 'sends no mail'

        context 'but group member is allowed individually' do
          let(:recipient) do
            FactoryBot.create(:user,
                              mail_notification: 'only_assigned',
                              member_in_project: project,
                              member_with_permissions: [:view_work_packages])
          end

          it_behaves_like 'sends mail'
        end
      end
    end

    shared_examples_for 'mentioned' do
      context 'for users' do
        context "mentioned is allowed to view the work package" do
          context "The added text contains a login name" do
            let(:note) { "Hello user:\"#{recipient.login}\"" }

            context "that is pretty normal word" do
              it_behaves_like 'sends mail'
            end

            context "that is an email address" do
              let(:recipient) do
                FactoryBot.create(:user,
                                  mail_notification: 'only_assigned',
                                  member_in_project: project,
                                  member_through_role: role,
                                  login: "foo@bar.com")
              end

              it_behaves_like 'sends mail'
            end
          end

          context "The added text contains a user ID" do
            let(:note) { "Hello user##{recipient.id}" }

            it_behaves_like 'sends mail'
          end

          context "The added text contains a user mention tag in one way" do
            let(:note) do
              <<~NOTE
                Hello <mention class="mention" data-id="#{recipient.id}" data-type="user" data-text="@#{recipient.name}">@#{recipient.name}</mention>
              NOTE
            end

            it_behaves_like 'sends mail'
          end

          context "The added text contains a user mention tag in the other way" do
            let(:note) do
              <<~NOTE
                Hello <mention class="mention" data-type="user" data-id="#{recipient.id}" data-text="@#{recipient.name}">@#{recipient.name}</mention>
              NOTE
            end

            it_behaves_like 'sends mail'
          end

          context "the recipient turned off all mail notifications" do
            let(:recipient) do
              FactoryBot.create(:user,
                                member_in_project: project,
                                member_through_role: role,
                                mail_notification: 'none')
            end

            let(:note) do
              "Hello user:\"#{recipient.login}\", hey user##{recipient.id}"
            end

            it_behaves_like 'sends no mail'
          end
        end

        context "mentioned user is not allowed to view the work package" do
          let(:recipient) do
            FactoryBot.create(:user,
                              mail_notification: 'only_assigned',
                              login: "foo@bar.com")
          end
          let(:note) do
            "Hello user:#{recipient.login}, hey user##{recipient.id}"
          end

          it_behaves_like 'sends no mail'
        end
      end

      # TODO: test for group mention.
      # Probably need to distinguish between user and group in mention tag
      context 'for groups' do
        let(:recipient) do
          FactoryBot.create(:user,
                            mail_notification: 'only_assigned')
        end

        let(:group) do
          FactoryBot.create(:group, members: recipient) do |group|
            Members::CreateService
              .new(user: nil, contract_class: EmptyContract)
              .call(project: project, principal: group, roles: [role])
          end
        end

        context 'on a hash/id based mention' do
          let(:note) do
            "Hello group##{group.id}"
          end

          it_behaves_like 'group mention'
        end

        context 'on a tag based mention with the type after' do
          let(:note) do
            <<~NOTE
              Hello <mention class="mention" data-id="#{group.id}" data-type="group" data-text="@#{group.name}">@#{group.name}</mention>
            NOTE
          end

          it_behaves_like 'group mention'
        end

        context 'on a tag based mention with the type before' do
          let(:note) do
            <<~NOTE
              Hello <mention data-type="group" class="mention" data-id="#{group.id}" data-text="@#{group.name}">@#{group.name}</mention>
            NOTE
          end

          it_behaves_like 'group mention'
        end
      end
    end

    context 'in the journal notes' do
      let(:journal) { journal_2_with_notes }
      let(:journal_2_with_notes) do
        work_package.add_journal author, note
        work_package.save(validate: false)
        work_package.journals.last
      end

      it_behaves_like 'mentioned'
    end

    context 'in the description' do
      let(:journal) { journal_2_with_description }
      let(:journal_2_with_description) do
        work_package.description = note
        work_package.save(validate: false)
        work_package.journals.last
      end

      it_behaves_like 'mentioned'
    end

    context 'in the subject' do
      let(:journal) { journal_2_with_subject }
      let(:journal_2_with_subject) do
        work_package.subject = note
        work_package.save(validate: false)
        work_package.journals.last
      end

      it_behaves_like 'mentioned'
    end
  end

  context 'aggregated journal is empty' do
    let(:journal) { journal_2_empty_change }
    let(:journal_2_empty_change) do
      work_package.add_journal(author, 'temp')
      work_package.save(validate: false)
      work_package.journals.last.tap do |j|
        j.update_column(:notes, nil)
      end
    end

    it_behaves_like 'sends no mail'
  end
end

describe 'initialization' do
  it 'subscribes the listener' do
    expect(Notifications::JournalWpMailService).to receive(:call)

    OpenProject::Notifications.send(
      OpenProject::Events::AGGREGATED_WORK_PACKAGE_JOURNAL_READY,
      journal: double('journal', initial?: true, journable: double('WorkPackage'))
    )
  end
end
