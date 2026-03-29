require 'csv'

input_fn = ARGV.shift
t_col = ARGV.shift
out_fn = ARGV.shift 

csv = CSV.read(input_fn, headers:true)
query_a = csv[t_col]
query_a.uniq!

File.open(out_fn, "w") { it.puts query_a }

