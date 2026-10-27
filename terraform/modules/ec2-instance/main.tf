locals {
  user_data = <<-EOT
    #cloud-config
    hostname: ${var.name}
    fqdn: ${var.name}.${var.domain}
    preserve_hostname: false
    prefer_fqdn_over_hostname: true
  EOT
}

resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  private_ip                  = var.private_ip
  vpc_security_group_ids      = var.security_group_ids
  key_name                    = var.key_name
  associate_public_ip_address = var.allocate_eip
  source_dest_check           = var.source_dest_check
  user_data                   = local.user_data

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = var.root_volume_size
    encrypted             = true
    delete_on_termination = true
  }

  tags = merge(var.tags, {
    Name = var.name
  })

  # Servers are patched in place with dnf, not replaced when a newer image
  # is published.
  lifecycle {
    ignore_changes = [ami, user_data]
  }
}

resource "aws_eip" "this" {
  count    = var.allocate_eip ? 1 : 0
  domain   = "vpc"
  instance = aws_instance.this.id

  tags = {
    Name = "${var.name}-eip"
  }
}

resource "aws_ebs_volume" "extra" {
  for_each = var.extra_volumes

  availability_zone = aws_instance.this.availability_zone
  size              = each.value.size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name = "${var.name}-${each.key}"
  }
}

resource "aws_volume_attachment" "extra" {
  for_each = var.extra_volumes

  device_name = each.value.device_name
  volume_id   = aws_ebs_volume.extra[each.key].id
  instance_id = aws_instance.this.id
}