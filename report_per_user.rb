require 'git'
require 'logger'
require 'time'

base_working_dir = '/repos/git'
repositories = %w{repo_name}

logger =  Logger.new(STDOUT)
logger.level = Logger::WARN

def history
  g.log.since('40 weeks ago').each do |log|
  g.diff(log.parent,log.sha).stats
end


git_monthly_report = {}
repositories.each do |repository|
  repository_path = "#{base_working_dir}/#{repository}"
  g = Git.open(repository_path, :log => logger)
  logs = g.log(Float::INFINITY).since('2022-01-01')
  authors = logs.map{|log| log.author.email.split('@').first}.uniq.compact
  logs_by_months = logs.group_by{|log| log.date.month}
  logs_by_months.each do |month, logs|
    git_monthly_report[month] ||= {}
    puts month
    authors.each do |author|
      git_monthly_report[month][author] ||= {}
      git_monthly_report[month][author][repository] ||= {:inserted => 0, :deleted => 0}
      puts author
      author_logs = logs.find_all{|log| /#{author}@.*/.match(log.author.email)}
      next if author_logs.count == 0
      latest_commit = author_logs.first.sha
      oldest_commit = author_logs.last.sha
      stats = 'git log --author="' + author + '" --numstat --pretty="%H" ' + " #{oldest_commit}^..#{latest_commit}" + ' |  awk \'NF==3 {plus+=$1; minus+=$2} END {printf("%d, %d\n", plus, minus)}\' '
      stats_output = `cd #{base_working_dir}/#{repository} && #{stats}`.chomp
      git_monthly_report[month][author][repository][:inserted], git_monthly_report[month][author][repository][:deleted] = stats_output.split(',').map{|s| s.to_i}
    end
  end
end
require 'pp'
require 'spreadsheet'
require 'mail'

format = Spreadsheet::Format.new(:color => :black, :weight => :bold, :size => 10)
report = Spreadsheet::Workbook.new

git_monthly_report.each do |month, stats|
  row_index = 0
  sheet = report.create_worksheet :name => "Stats GIT month #{month}"
  sheet.row(0).default_format = format
  repositories.each_with_index do |repository,index|
    sheet[row_index,index * 3 + 2] = repository
    sheet.merge_cells(row_index, index * 3 + 2, row_index,  index * 3 + 3)
    sheet[row_index + 1,index * 3 + 2] = 'Inserted'
    sheet[row_index + 1,index * 3 + 3] = 'Deleted'
  end
  row_index += 2

  stats.each do |author, repositories_stats|
    sheet[row_index ,0] = author
    repositories.each_with_index do |repository,index|
      if repositories_stats.has_key?(repository)
        sheet[row_index ,index * 3 + 2] = repositories_stats[repository][:inserted]
        sheet[row_index ,index * 3 + 3] = repositories_stats[repository][:deleted]
      else
        sheet[row_index ,index * 3 + 2] = 0
        sheet[row_index ,index * 3 + 3] = 0
      end
    end
    row_index += 1
  end
end

report.write '/tmp/git_stats.xls'
sender_address = "no-reply@domain.com"
mail_subject = "Stats GIT"
mail_body = "Git stats per user"

RECIPIENTS = ['your@email.com']

RECIPIENTS.each do |recipient_address|
  message = Mail.new
  message.charset = 'UTF-8'
  message.content_transfer_encoding = "8bit"
  message.from = sender_address
  message.to = recipient_address
  message.subject mail_subject
  message.body mail_body
  message.add_file :filename => '/tmp/git_stats.xls'
  message.delivery_method :smtp, :address => "localhost", :port => 25
  message.deliver!
  puts "Reports sent to #{recipient_address}"
end
