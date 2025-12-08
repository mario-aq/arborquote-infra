require_relative 'lambda/shared/db_client'

result = ResponseHelper.success(200, { message: 'test' })
puts "Result: #{result.inspect}"
puts "statusCode: #{result[:statusCode]}"
puts "statusCode with string: #{result['statusCode']}"
