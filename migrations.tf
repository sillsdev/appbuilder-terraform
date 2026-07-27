moved {
  from = module.vpc.aws_vpc.vpc
  to   = module.vpc.aws_vpc.this[0]
}

moved {
  from = module.vpc.aws_subnet.public_subnet[0]
  to   = module.vpc.aws_subnet.public[0]
}

moved {
  from = module.vpc.aws_subnet.public_subnet[1]
  to   = module.vpc.aws_subnet.public[1]
}

moved {
  from = module.vpc.aws_internet_gateway.internet_gateway
  to   = module.vpc.aws_internet_gateway.this[0]
}

moved {
  from = module.vpc.aws_route_table.igw_route_table
  to   = module.vpc.aws_route_table.public[0]
}

moved {
  from = module.vpc.aws_route.igw_route
  to   = module.vpc.aws_route.public_internet_gateway[0]
}

moved {
  from = module.vpc.aws_route_table_association.public_route[0]
  to   = module.vpc.aws_route_table_association.public[0]
}

moved {
  from = module.vpc.aws_route_table_association.public_route[1]
  to   = module.vpc.aws_route_table_association.public[1]
}

moved {
  from = module.vpc.aws_db_subnet_group.db_subnet_group
  to   = aws_db_subnet_group.vpc_public
}

moved {
  from = module.cloudflare-sg.aws_security_group.cloudflare_https
  to   = aws_security_group.cloudflare
}

moved {
  from = module.cloudflare-sg.aws_security_group_rule.cloudflare_ipv4
  to   = aws_security_group_rule.cloudflare
}
