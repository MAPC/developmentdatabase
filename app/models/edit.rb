class Edit < ActiveRecord::Base
  extend Enumerize

  has_many :fields, class_name: :FieldEdit, dependent: :destroy

  belongs_to :editor,    class_name: :User
  belongs_to :moderator, class_name: :User
  belongs_to :development

  validates :development, presence: true
  validates :editor, presence: true
  validates :state,  presence: true
  # Disabled until we can get the edit form working with this.
  # validates :log_entry, presence: true, length: { minimum: 25, maximum: 2000 }
  validates :moderated_at, presence: true, if: -> { approved? || declined? }
  # validate  :applied_only_if_approved

  enumerize :state, in: [:pending, :approved, :declined],
    default: :pending, predicates: true

  def self.applied
    where(applied: true).order(applied_at: :desc)
  end

  def self.pending
    where(state: :pending).where(applied: false).order(created_at: :asc)
  end

  def self.since(time = Time.now)
    where 'applied_at > ?', time
  end

  # TODO: Do these belong here, if the service is handling
  # the alteration of state?
  def approved
    assign_attributes(moderated_at: Time.now, state: :approved)
  end

  def declined
    assign_attributes(moderated_at: Time.now, state: :declined)
  end

  def applied
    assign_attributes(applied_at: Time.now, applied: true)
  end

  def approve!
    Services::Edit::Approve.new(self).call
  end

  def decline!
    Services::Edit::Decline.new(self).call
  end

  # The edit can be applied if:
  # - it's not already applied AND
  # - there's no conflict OR there is a conflict but it is ignored.
  def applyable?
    applied? ? false : true
  end

  def moderated?
    moderated_at.presence || approved? || declined?
  end

  def moderatable?
    !moderated?
  end

  def conflicts
    fields.map do |field|
      { name: field.name, conflict: field.conflict } if field.conflict?
    end.compact
  end

  def diff
    fields.map { |field| { name: field.name }.merge(field.change) }
  end

  def assignable
    # Could also be written referencing #diff, and rejecting a key.
    # Or send a parameter to diff to reject a key.
    Hash[fields.map { |f| [f.name, f.to] }]
  end

  private

  def applied_only_if_approved
    # The state must be :approved if applied = true
    if applied == true && state.to_sym != :approved
      errors.add(:applied, 'can only be set if the edit is approved')
    end
  end

end
