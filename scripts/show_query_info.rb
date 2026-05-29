require 'csv'
require 'optparse'

params = ARGV.getopts("","query:","info:")

csv = CSV.read(params["info"], headers:true)
t_index = csv["Sequence_ID"].index(params["query"])

p csv[t_index]