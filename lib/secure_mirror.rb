require 'json'
require 'logger'
require 'inifile'
require 'octokit'

# interface and setup for the correct secure-mirror repo implementation
class SecureMirror
  @repo = nil
  @config = nil
  @git_config = nil
  @logger = nil

  attr_reader :repo

  def new_repo?
    @git_config.nil?
  end

  def mirror?
    !@mirror_cfg.empty?
  end

  def misconfigured?
    @mirror_cfg.size > 1
  end

  def mirror_name
    return '' unless mirror?
    @mirror_cfg[0][0]
  end

  def url
    return '' unless mirror_name
    @git_config[mirror_name]['url']
  end

  def name
    return '' unless mirror_name
    url = @git_config[mirror_name]['url']
    # can't use ruby's URI, it *won't* parse git ssh urls
    # case examples:
    #   git@github.com:LLNL/SSHSpawner.git
    #   https://github.com/tgmachina/test-mirror.git
    url.split(':')[-1]
       .gsub('.git', '')
       .split('/')[-2..-1]
       .join('/')
  end

  def init_mirror_info
    # pull all the remotes out of the config except the one marked "upstream"
    @mirror_cfg = @git_config.select do |k, v|
      k.include?('remote') && !k.include?('upstream') && v.include?('mirror')
    end
  end

  def init_github_repo
    require 'github_repo'
    config = @config[:repo_types][:github]
    return unless config
    clients = {}
    config[:access_tokens].each do |type, token|
      clients[type] = Octokit::Client.new(per_page: 1000, access_token: token)
    end
    GitHubRepo.new(@hook_args,
                   clients: clients,
                   trusted_org: config[:trusted_org],
                   signoff_body: config[:signoff_body],
                   logger: @logger)
  end

  def repo_from_config
    case url.downcase
    when /github/
      init_github_repo
    end
  end

  def initialize(hook_args, config_file, git_config_file, logger)
    # `pwd` for the hook will be the git directory itself
    @logger = logger
    conf = File.open(config_file)
    @config = JSON.parse(conf.read, symbolize_names: true)
    @git_config = IniFile.load(git_config_file)
    return unless @git_config
    init_mirror_info
    @hook_args = hook_args
    @hook_args[:repo_name] = name
    return if new_repo?
    @repo = repo_from_config
  end
end

def evaluate_changes(config_file: 'config.json',
                     git_config_file: Dir.pwd + '/config',
                     log_file: 'mirror.log')
  # the environment variables are provided by the git update hook
  hook_args = {
    ref_name: ARGV[0],
    current_sha: ARGV[1],
    future_sha: ARGV[2]
  }

  logger = Logger.new(log_file)
  logger.level = ENV['SM_LOG_LEVEL'] || Logger::INFO
  begin
    sm = SecureMirror.new(hook_args, config_file, git_config_file, logger)

    # if this is a brand new repo, or not a mirror allow the import
    if sm.new_repo?
      logger.info('Brand new repo, cannot read git config info')
      return 0
    elsif !sm.mirror?
      logger.info('Repo %s is not a mirror' % sm.name)
      return 0
    end

    # fail on invalid git config
    if sm.misconfigured?
      logger.error('Repo %s is misconfigured' % sm.name)
      return 1
    end

    # if repo initialization was successful and we trust the change, allow it
    if sm.repo && sm.repo.trusted_change?
      logger.info('Importing trusted changes from %s' % sm.name)
      return 0
    end
  rescue StandardError => err
    # if anything goes wrong, cancel the changes
    logger.error(err)
    return 1
  end

  1
end