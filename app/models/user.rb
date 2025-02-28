class User < ActiveRecord::Base
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable

  # include Authority::UserAbilities
  extend Enumerize

  before_save :hash_email
  before_save :ensure_reasonable_last_checked
  before_create :set_initial_last_checked
  after_create :assign_api_key

  attr_readonly :api_key

  has_one  :api_key, dependent: :destroy

  has_many :edits, foreign_key: :editor_id
  has_many :contributions,
    -> { where(applied: true) },
    class_name: 'Edit',
    foreign_key: :editor_id

  has_many :searches, -> { where(saved: true) }
  has_many :memberships, dependent: :destroy
  has_many :organizations,
    -> { includes(:memberships).where(memberships: { state: :active }) },
    through: :memberships

  has_many :subscriptions

  enumerize :mail_frequency, in: [:never, :daily, :weekly],
    predicates: true, default: :weekly

  # TODO: Rewrite as SQL or relation
  def moderated_developments
    if member_of_admin_org?
      Development.includes(:edits).where(edits: { state: :pending })
    else
      organizations.flat_map(&:_developments)
    end
  end

  def owned_organizations
    organizations.includes(:memberships).where(memberships: { role: :admin })
  end

  def member_of?(organization, state: :active)
    memberships.where(state: state, organization_id: organization.id).any?
  end

  def moderator_for?(development)
    [
      # Development team members cannot moderate developments at this time.
      # member_of_development_team?(development),
      moderated_developments.include?(development),
      member_of_municipal_org?(development),
      member_of_admin_org?
    ].any?
  end

  def admin_of?(organization)
    organization.admins.include? self
  end

  # Is the user a member of an organization which is on the development team
  # for this development?
  def member_of_development_team?(development)
    (organizations & development.team_members).any?
  end

  # Is the user a member of a municipal organization whose municipality
  # contains this development
  def member_of_municipal_org?(development)
    organizations.municipal_in(development.municipality).any?
  end

  # Do the organizations this user belongs to intersect with the organizations
  # that have admin privileges?
  def member_of_admin_org?
    (organizations & Organization.admin).any?
  end

  def subscribe(subscribable)
    subscriptions.create(subscribable: subscribable)
  end

  def unsubscribe(subscribable)
    subscriptions.where(subscribable: subscribable).first.destroy
  end

  def subscribed?(subscribable)
    subscriptions.where(subscribable: subscribable).present?
  end

  alias_method :subscribe_to,     :subscribe
  alias_method :unsubscribe_from, :unsubscribe
  alias_method :subscribed_to?,   :subscribed?

  def subscriptions_needing_update
    Subscription.where(id: subscriptions.select(&:needs_update?).map(&:id))
  end

  def known?
    !anonymous?
  end

  def anonymous?
    self == User.null
  end

  def self.null
    @null ||= new(email: '<Null User>')
  end

  private

  def hash_email
    self.hashed_email = Digest::MD5.hexdigest(email.downcase)
  end

  def ensure_reasonable_last_checked
    if mail_frequency_change && mail_frequency_change.last != 'never'
      self.last_checked_subscriptions = 1.week.ago
    end
  end

  def set_initial_last_checked
    self.last_checked_subscriptions = created_at
  end

  def assign_api_key
    APIKey.create!(user: self)
  end
end
