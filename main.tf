

resource "aws_vpc" "VPC" {
  cidr_block           = var.vpcCIDR
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = {
    Name = "APWPMS"
  }
}

resource "aws_subnet" "Public_Subnet" {
  cidr_block              = var.CIDR_Pub_Subnet
  vpc_id                  = aws_vpc.VPC.id
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"
  tags = {
    Name = "Public Subnet"
  }
}

resource "aws_subnet" "Private_Subnet" {
  cidr_block = var.CIDR_Pr_Subnet
  vpc_id     = aws_vpc.VPC.id
  tags = {
    Name = "Private Subnet"
  }
}

resource "aws_internet_gateway" "InternetGateway" {
  vpc_id = aws_vpc.VPC.id
  tags = {
    Name = "IGW for APWP(Pb Subnet)"
  }
}

resource "aws_route_table" "PbRouteTable" {
  vpc_id = aws_vpc.VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.InternetGateway.id
  }

  tags = {
    Name = "Route Table for Pb Subnet"
  }
}

resource "aws_route_table_association" "SubnetAssociationFrPBRT" {
  subnet_id      = aws_subnet.Public_Subnet.id
  route_table_id = aws_route_table.PbRouteTable.id
}

resource "aws_eip" "MyEIP" {
  vpc = true
}

resource "aws_nat_gateway" "NatGateway" {
  allocation_id = aws_eip.MyEIP.id
  subnet_id     = aws_subnet.Public_Subnet.id
}

resource "aws_route_table" "PrRouteTable" {
  vpc_id = aws_vpc.VPC.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.NatGateway.id
  }

  tags = {
    Name = "Route Table for Pr Subnet"
  }
}

resource "aws_route_table_association" "SubnetAssociationFrPRRT" {
  subnet_id      = aws_subnet.Private_Subnet.id
  route_table_id = aws_route_table.PrRouteTable.id
}


resource "aws_security_group" "APWPInnerSg" {
  name        = "SgforAPWP"
  description = "Allow all resources through http to via lbsg as source"
  vpc_id      = aws_vpc.VPC.id

  ingress {
    description     = "Allow all resources through http to via lbsg as source"
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.LbSecurityGroup.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "SecurityGroupFrPrInstance" {
  name   = "SgforPrivateSubnetInstance"
  vpc_id = aws_vpc.VPC.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.APWPInnerSg.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "InstanceforAPWP" {
  ami             = "ami-09d3b3274b6c5d4aa"
  instance_type   = var.Instance_Type_APWP
  subnet_id       = aws_subnet.Public_Subnet.id
  key_name        = "Servers"
  security_groups = [aws_security_group.APWPInnerSg.id]
  user_data       = <<-EOF
                    #!/bin/bash
                    sudo apt-get update -y
                    sudo apt-get install apache2 -y
                    sudo /etc/init.d/apache2 start
                    sudo apt-get install mysql-client -y
                    sudo apt-get install php libapache2-mod-php php-mysql -y
                    sudo /etc/init.d/apache2 restart
                    wget http://wordpress.org/latest.zip
                    sudo apt install unzip
                    unzip -q latest.zip -d /var/www/html
                    chown -R www-data:www-data /var/www/html/wordpress
                    chmod -R 755 /var/www/html/wordpress
                    mkdir -p /var/www/html/wordpress/wp-content/uploads
                    chown -R www-data:www-data /var/www/html/wordpress/wp-content/uploads
                    sudo service apache2 restart
                    EOF
  tags = {
    "Name" = "Instance for Apache-PHP and Wordpress"
  }
}
resource "aws_instance" "InstanceforMySQL" {
  ami             = "ami-0a91cd140a1fc148a"
  instance_type   = var.Instance_Type_DB
  subnet_id       = aws_subnet.Private_Subnet.id
  key_name        = "Servers"
  security_groups = [aws_security_group.SecurityGroupFrPrInstance.id]
  user_data       = <<-EOF
                    #!/bin/bash
                    sudo su
                    sudo apt-get update -y
                    sudo apt-get install mysql-server -y
                    sudo apt-get install php libapache2-mod-php php-mysql -y
                    sudo mysql -u root -pVasanthi@24 -e "CREATE DATABASE WordpressInfo DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
                    sudo mysql -u root -pVasanthi@24 -e "use WordpressInfo;"
                    sudo mysql -u root -pVasanthi@24 -e "create user 'vignesh'@'%' identified by 'Vasanthi@24';"
                    sudo mysql -u root -pVasanthi@24 -e "grant all on WordpressInfo.* to 'vignesh'@'%';"
                    sudo mysql -u root -pVasanthi@24 -e "GRANT ALL PRIVILEGES ON WordpressInfo.* TO 'vignesh'@'%';"
                    sudo mysql -u root -pVasanthi@24 -e "FLUSH PRIVILEGES;"
                    sed -i 's/127.0.0.1/0.0.0.0/g' /etc/mysql/mysql.conf.d/mysqld.cnf
                    sudo service mysql restart
                    EOF
  tags = {
    "Name" = "Instance for MySQL"
  }
}

resource "aws_subnet" "Public_Subnet2" {
  cidr_block        = "10.0.3.0/24"
  vpc_id            = aws_vpc.VPC.id
  availability_zone = "us-east-1a"
  tags = {
    Name = "Extra Public Subnet for LB"
  }
}

resource "aws_launch_configuration" "LaunchConfiguration" {
  name                        = "APWPLC"
  image_id                    = "ami-03946fd338928596f"
  instance_type               = "t2.micro"
  associate_public_ip_address = true
  key_name                    = "Servers"
  security_groups             = [aws_security_group.APWPInnerSg.id]
  user_data                   = <<-EOF
                                #!/bin/bash
                                sudo apt-get install mysql-client -y
                                sudo service apache2 restart
                                EOF              
}





